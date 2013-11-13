package Kossy;

use strict;
use warnings;
use utf8;
use Carp qw//;
use Scalar::Util qw//;
use Cwd qw//;
use File::Basename qw//;
use Text::Xslate;
use HTML::FillInForm::Lite qw//;
use Try::Tiny;
use Encode;
use Router::Boom;
use Class::Accessor::Lite (
    new => 0,
    rw => [qw/root_dir/]
);
use base qw/Exporter/;

our $VERSION = '0.23';
our @EXPORT = qw/new root_dir psgi build_app _router _connect get post router filter _wrap_filter/;

sub new {
    my $class = shift;
    my %args;
    if ( @_ < 2 ) {
        my $root_dir = shift;
        my @caller = caller;
        $root_dir ||= File::Basename::dirname( Cwd::realpath($caller[1]) );
        $args{root_dir} = $root_dir;
    }
    else {
        %args = @_;
    }

    bless \%args, $class;
}

sub psgi {
    my $self = shift;
    if ( ! ref $self ) {
        my $root_dir = shift;
        my @caller = caller;
        $root_dir ||= File::Basename::dirname( Cwd::realpath($caller[1]) );
        $self = $self->new($root_dir);
    }

    $self->build_app;
}

sub build_app {
    my $self = shift;

    #router
    my $router = Router::Boom->new;
    $router->add($_ => $self->_router->{$_} ) for keys %{$self->_router};

    #xslate
    my $fif = HTML::FillInForm::Lite->new();
    my $tx = Text::Xslate->new(
        path => [ $self->root_dir . '/views' ],
        input_layer => ':utf8',
        module => ['Text::Xslate::Bridge::TT2Like','Number::Format' => [':subs']],
        function => {
            fillinform => sub {
                my $q = shift;
                return sub {
                    my ($html) = @_;
                    return Text::Xslate::mark_raw( $fif->fill( \$html, $q ) );
                }
            }
        },
    );

    sub {
        my $env = shift;
        try {
            my $c = Kossy::Connection->new({
                tx => $tx,
                req => Kossy::Request->new($env),
                res => Kossy::Response->new(200, ['Content-Type' => 'text/html; charset=UTF-8']),
                stash => {},
            });
            my ($match,$args) = try {
                my $path_info = Encode::decode_utf8( $env->{PATH_INFO},  Encode::FB_CROAK | Encode::LEAVE_SRC );
                my @match = $router->match($path_info);
                if ( !@match ) {
                    $c->halt(404);
                }

                my $method = uc $env->{REQUEST_METHOD};
                if ( !exists $match[0]->{$method}) {
                    $c->halt(405);
                }
                return ($match[0]->{$method},$match[1]);
            } catch {
                if ( ref $_ && ref $_ eq 'Kossy::Exception' ) {
                    die $_; #rethrow
                }
                $c->halt(400,'unexpected character in request');
            };
            
            my $code = $match->{__action__};
            my $filters = $match->{__filter__} || [];
            $c->args($args);
            my $app = sub {
                my ($self, $c) = @_;
                my $response;
                my $res = $code->($self, $c);
                Carp::croak "Undefined Response" if !$res;
                my $res_t = ref($res) || '';
                if ( Scalar::Util::blessed $res && $res->isa('Kossy::Response') ) {
                    $response = $res;;
                }
                elsif ( Scalar::Util::blessed $res && $res->isa('Plack::Response') ) {
                    $response = bless $res, 'Kossy::Response';
                }
                elsif ( $res_t eq 'ARRAY' ) {
                    $response = Kossy::Response->new(@$res);
                }
                elsif ( !$res_t ) {
                    $c->res->body($res);
                    $response = $c->res;
                }
                else {
                    Carp::croak sprintf "Unknown Response: %s", $res_t;
                }
                $response;
            };
            
            for my $filter ( reverse @$filters ) {
                $app = $self->_wrap_filter($filter,$app);
            }
            # do all
            $app->($self, $c)->finalize;
        } catch {
            if ( ref $_ && ref $_ eq 'Kossy::Exception' ) {
                return $_->response;
            }
            die $_;
        };
    };
}



my $_ROUTER={};
sub _router {
    my $klass = shift;
    my $class = ref $klass ? ref $klass : $klass; 
    if ( !$_ROUTER->{$class} ) {
        $_ROUTER->{$class} = {};
    }    
    $_ROUTER->{$class};
}

sub _connect {
    my $class = shift;
    my ( $methods, $pattern, $filter, $code ) = @_;
    $methods = ref($methods) ? $methods : [$methods];
    if (!$code) {
        $code = $filter;
        $filter = [];
    }
    for my $method ( @$methods ) {
        $class->_router->{$pattern}->{$method} = {
            __action__ => $code,
            __filter__ => $filter
        };
    }
}

sub get {
    my $class = caller;
    $class->_connect( ['GET','HEAD'], @_  );
}

sub post {
    my $class = caller;
    $class->_connect( ['POST'], @_  );
}

sub router {
    my $class = caller;
    $class->_connect( @_  );
}

my $_FILTER={};
sub filter {
    my $class = caller;
    if ( !$_FILTER->{$class} ) {
        $_FILTER->{$class} = {};
    }    
    if ( @_ ) {
        $_FILTER->{$class}->{$_[0]} = $_[1];
    }
    $_FILTER->{$class};
}

sub _wrap_filter {
    my $klass = shift;
    my $class = ref $klass ? ref $klass : $klass; 
    if ( !$_FILTER->{$class} ) {
        $_FILTER->{$class} = {};
    }
    my ($filter,$app) = @_;
    my $filter_subref = $_FILTER->{$class}->{$filter};
    Carp::croak sprintf("Filter:%s is not exists", $filter) unless $filter_subref;    
    return $filter_subref->($app);
}

package Kossy::Exception;

use strict;
use warnings;
use HTTP::Status;
use Text::Xslate qw/html_escape/;

sub new {
    my $class = shift;
    my $code = shift;
    my %args = (
        code => $code,
    );
    if ( @_ == 1 ) {
        $args{message} = shift;
    }
    elsif ( @_ % 2 == 0) {
        %args = (
            %args,
            @_
        );
    }
    bless \%args, $class;
}

sub response {
    my $self = shift;
    my $code = $self->{code} || 500;
    my $message = $self->{message};
    $message ||= HTTP::Status::status_message($code);

    my @headers = (
         'Content-Type' => q!text/html; charset=UTF-8!,
    );

    if ($code =~ /^3/ && (my $loc = eval { $self->{location} })) {
        push(@headers, Location => $loc);
    }

    return Kossy::Response->new($code, \@headers, [$self->html($code,$message)])->finalize;
}

sub html {
    my $self = shift;
    my ($code,$message) = @_;
    $code = html_escape($code);
    $message = html_escape($message);
    return <<EOF;
<!doctype html>
<html>
<head>
<meta charset=utf-8 />
<style type="text/css">
.message {
  font-size: 200%;
  margin: 20px 20px;
  color: #666;
}
.message strong {
  font-size: 250%;
  font-weight: bold;
  color: #333;
}
</style>
</head>
<body>
<p class="message">
<strong>$code</strong> $message
</p>
</div>
</body>
</html>
EOF
}

package Kossy::Connection;

use strict;
use warnings;
use Class::Accessor::Lite (
    new => 1,
    rw => [qw/req res stash args tx debug/]
);
use JSON qw//;

my $_JSON = JSON->new()->allow_blessed(1)->convert_blessed(1)->ascii(1);

# for IE7 JSON venularity.
# see http://www.atmarkit.co.jp/fcoding/articles/webapp/05/webapp05a.html
# Copy from Amon2::Plugin::Web::JSON => Fixed to escape only string parts
my %_ESCAPE = (
    '+' => '\\u002b', # do not eval as UTF-7
    '<' => '\\u003c', # do not eval as HTML
    '>' => '\\u003e', # ditto.
);
sub escape {
    my $self = shift;
    my $body = shift;
    $body =~ s!([+<>])!$_ESCAPE{$1}!g;
    return qq("$body");
}
sub escape_json {
    my $self = shift;
    my $body = shift;
    # escape only string parts
    $body =~ s/"((?:\\"|[^"])*)"/$self->escape($1)/eg;
    return $body;
}

*request = \&req;
*response = \&res;

sub halt {
    my $self = shift;
    die Kossy::Exception->new(@_);
}

sub redirect {
    my $self = shift;
    $self->res->redirect(@_);
    $self->res;
}

sub render {
    my $self = shift;
    my $file = shift;
    my %args = ( @_ && ref $_[0] ) ? %{$_[0]} : @_;
    my %vars = (
        c => $self,
        stash => $self->stash,
        %args,
    );

    my $body = $self->tx->render($file, \%vars);
    $self->res->status( 200 );
    $self->res->content_type('text/html; charset=UTF-8');
    $self->res->body( $body );
    $self->res;
}

sub render_json {
    my $self = shift;
    my $obj = shift;

    # defense from JSON hijacking
    # Copy from Amon2::Plugin::Web::JSON
    if ( !$self->req->header('X-Requested-With')  && 
         ($self->req->user_agent||'') =~ /android/i &&
         defined $self->req->header('Cookie') &&
         ($self->req->method||'GET') eq 'GET'
    ) {
        $self->halt(403,"Your request is maybe JSON hijacking.\nIf you are not a attacker, please add 'X-Requested-With' header to each request.");
    }

    my $body = $_JSON->encode($obj);
    $body = $self->escape_json($body);

    if ( ( $self->req->user_agent || '' ) =~ m/Safari/ ) {
        $body = "\xEF\xBB\xBF" . $body;
    }

    $self->res->status( 200 );
    $self->res->content_type('application/json; charset=UTF-8');
    $self->res->header( 'X-Content-Type-Options' => 'nosniff' ); # defense from XSS
    $self->res->body( $body );
    $self->res;    
}


package Kossy::Request;

use strict;
use warnings;
use parent qw/Plack::Request/;
use Hash::MultiValue;
use Encode;
use Kossy::Validator;

sub body_parameters {
    my ($self) = @_;
    $self->{'kossy.body_parameters'} ||= $self->_decode_parameters($self->SUPER::body_parameters());
}

sub query_parameters {
    my ($self) = @_;
    $self->{'kossy.query_parameters'} ||= $self->_decode_parameters($self->SUPER::query_parameters());
}

sub _decode_parameters {
    my ($self, $stuff) = @_;

    my @flatten = $stuff->flatten();
    my @decoded;
    while ( my ($k, $v) = splice @flatten, 0, 2 ) {
        push @decoded, Encode::decode_utf8($k), Encode::decode_utf8($v);
    }
    return Hash::MultiValue->new(@decoded);
}
sub parameters {
    my $self = shift;
    $self->env->{'kossy.request.merged'} ||= do {
        my $query = $self->query_parameters;
        my $body  = $self->body_parameters;
        Hash::MultiValue->new( $query->flatten, $body->flatten );
    };
}

sub body_parameters_raw {
    shift->SUPER::body_parameters();
}
sub query_parameters_raw {
    shift->SUPER::query_parameters();
}

sub parameters_raw {
    my $self = shift;
    $self->env->{'plack.request.merged'} ||= do {
        my $query = $self->SUPER::query_parameters();
        my $body  = $self->SUPER::body_parameters();
        Hash::MultiValue->new( $query->flatten, $body->flatten );
    };
}

sub param_raw {
    my $self = shift;

    return keys %{ $self->parameters_raw } if @_ == 0;

    my $key = shift;
    return $self->parameters_raw->{$key} unless wantarray;
    return $self->parameters_raw->get_all($key);
}

sub base {
    my $self = shift;
    $self->{_base} ||= {};
    my $base = $self->_uri_base;
    $self->{_base}->{$base} ||= $self->SUPER::base;
    $self->{_base}->{$base}->clone;
}

sub uri_for {
     my($self, $path, $args) = @_;
     my $uri = $self->base;
     my $base = $uri->path eq "/"
              ? ""
              : $uri->path;
     $uri->path( $base . $path );
     $uri->query_form(@$args) if $args;
     $uri;
}

sub validator {
    my ($self, $rule) = @_;
    Kossy::Validator->check($self,$rule);
}

1;

package Kossy::Response;

use strict;
use warnings;
use parent qw/Plack::Response/;
use Encode;
use HTTP::Headers::Fast;

sub headers {
    my $self = shift;

    if (@_) {
        my $headers = shift;
        if (ref $headers eq 'ARRAY') {
            Carp::carp("Odd number of headers") if @$headers % 2 != 0;
            $headers = HTTP::Headers::Fast->new(@$headers);
        } elsif (ref $headers eq 'HASH') {
            $headers = HTTP::Headers::Fast->new(%$headers);
        }
        return $self->{headers} = $headers;
    } else {
        return $self->{headers} ||= HTTP::Headers::Fast->new();
    }
}

sub _body {
    my $self = shift;
    my $body = $self->body;
       $body = [] unless defined $body;
    if (!ref $body or Scalar::Util::blessed($body) && overload::Method($body, q("")) && !$body->can('getline')) {
        return [ Encode::encode_utf8($body) ] if Encode::is_utf8($body);
        return [ $body ];
    } else {
        return $body;
    }
}

sub finalize {
    my $self = shift;
    Carp::croak "missing status" unless $self->status();

    my @headers;
    $self->headers->scan(sub{
        my ($k,$v) = @_;
        return if $k eq 'X-Frame-Options' || $k eq 'X-XSS-Protection';
        $v =~ s/\015\012[\040|\011]+/chr(32)/ge; # replace LWS with a single SP
        $v =~ s/\015|\012//g; # remove CR and LF since the char is invalid here
        push @headers, $k, $v;
    });

    while (my($name, $val) = each %{$self->cookies}) {
        my $cookie = $self->_bake_cookie($name, $val);
        push @headers, 'Set-Cookie' => $cookie;
    }

    push @headers, 
#        'X-Frame-Options' => 'DENY',
        'X-XSS-Protection' => 1;

    return [
        $self->status,
        \@headers,
        $self->_body,
    ];
}

1;

__END__

=head1 NAME

Kossy - Sinatra-ish Simple and Clear web application framework

=head1 SYNOPSIS

  % kossy-setup MyApp
  % cd MyApp
  % plackup app.psgi
  
  ## lib/MyApp/Web.pm
  
  use Kossy;
  
  get '/' => sub {
      my ( $self, $c )  = @_;
      $c->render('index.tx', { greeting => "Hello!" });
  };
  
  get '/json' => sub {
      my ( $self, $c )  = @_;
      my $result = $c->req->validator([
          'q' => {
              default => 'Hello',
              rule => [
                  [['CHOICE',qw/Hello Bye/],'Hello or Bye']
              ],
          }
      ]);
      $c->render_json({ greeting => $result->valid->get('q') });
  };
  
  1;
  
  ## views/index.tx
  : cascade base
  : around content -> {
    <: $greeting :>
  : }

=head1 DESCRIPTION

Kossy is Sinatra-ish Simple and Clear web application framework, which is based upon L<Plack>, L<Router::Simple>, L<Text::Xslate> and build-in Form-Validator. That's suitable for small application and rapid development.

=head1 Kossy class

Kossy exports some methods to building application

=head2 CLASS METHODS for Kossy class

=over 4

=item my $kossy = Kossy->new( root_dir => $root_dir );

Create instance of the application object.

=back

=head2 OBJECT METHODS for Kossy class

=over 4

=item my $root_dir = $kossy->root_dir();

accessor to root directory of the application

=item my $app = $kossy->psgi();

return PSGI application

=back

=head2 DISPATCHER METHODS for Kossy class

=over 4

=item filter

makes application wrapper like plack::middlewares.

  filter 'set_title' => sub {
      my $app:CODE = shift;
      sub {
          my ( $self:Kossy, $c:Kossy::Connection )  = @_;
          $c->stash->{site_name} = __PACKAGE__;
          $app->($self,$c);
      }
  };

=item get path:String => [[filters] =>] CODE

=item post path:String => [[filters] =>] CODE

setup router and dispatch code

  get '/' => [qw/set_title/] => sub {
      my ( $self:Kossy, $c:Kossy::Connection )  = @_;
      $c->render('index.tx', { greeting => "Hello!" });
  };
  
  get '/json' => sub {
      my ( $self:Kossy, $c:Kossy::Connection )  = @_;
      $c->render_json({ greeting => "Hello!" });
  };

dispatch code shall return Kossy::Response object or PSGI response ArrayRef or String.

=item router 'HTTP_METHOD'|['METHOD'[,'METHOD']] => path:String => [[filters] =>] CODE

adds routing rule other than GET and POST

  router 'PUT' => '/put' => sub {
      my ( $self:Kossy, $c:Kossy::Connection )  = @_;
      $c->render_json({ greeting => "Hello!" });
  };

=back

=head1 Kossy::Connection class

per-request object, herds request and response

=head2 OBJECT METHODS for Kossy::Connection class

=over 4

=item req:Kossy::Request

=item res:Kossy::Response

=item stash:HashRef

=item args:HashRef

Router::Simple->match result

=item halt(status_code, message)

die and response immediately

=item redirect($uri,status_code): Kossy::Response

=item render($file,$args): Kossy::Response

calls Text::Xslate->render makes response. template files are searching in root_dir/views directory

template syntax is Text::Xslate::Syntax::Kolon, can use Kossy::Connection object and fillinform block.

   ## template.tx
   : block form |  fillinform( $c.req ) -> {
   <head>
   <title><: $c.stash.title :></title>
   </head>
   <body>
   <form action="<: $c.req.uri_for('/post') :>">
   <input type="text" size="10" name="title" />
   <textarea name="body" rows="20" cols="90"></textarea>
   </form>
   </body>
   : }

also can use L<Text::Xslate::Bridge::TT2Like> and L<Number::Format> methods in your template

=item render_json($args): Kossy::Response

serializes arguments with JSON and makes response

This method escapes '<', '>', and '+' characters by "\uXXXX" form. Browser don't detects the JSON as HTML. And also this module outputs "X-Content-Type-Options: nosniff" header for IEs.

render_json have a JSON hijacking detection feature same as L<Amon2::Plugin::Web::JSON>. This returns "403 Forbidden" response if following pattern request.

=over 8

=item The request have 'Cookie' header.

=item The request doesn't have 'X-Requested-With' header.

=item The request contains /android/i string in 'User-Agent' header.

=item Request method is 'GET'

=back

=back

=head1 Kossy::Request

This class is child class of Plack::Request, decode query/body parameters automatically. Return value of $req->param(), $req->body_parameters, etc. is the decoded value.

=head2 OBJECT METHODS for Kossy::Request class

=over 4

=item uri_for($path,$args):String

build absolute URI with path and $args

  my $uri = $c->req->uri_for('/login',[ arg => 'Hello']);  

=item validator($rule):Kossy::Validaor::Result

validate parameters using L<Kossy::Validatar>

  my $result = $c->req->validator([
    'q' => [['NOT_NULL','query must be defined']],
    'level' => {
        default => 'M',
        rule => [
            [['CHOICE',qw/L M Q H/],'invalid level char'],
        ],
    },
  ]);

  my $val = $result->valid('q');
  my $val = $result->valid('level');

=item body_parameters_raw

=item query_parameters_raw

=item parameters_raw

=item param_raw

These methods are the accessor to raw values. 'raw' means the value is not decoded.

=back

=head1 Kossy::Response

This class is child class of Plack::Response

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo {at} gmail.comE<gt>

=head1 SEE ALSO

Kossy is small waf, that has only 400 lines code. so easy to reading framework code and customize it. Sinatra-ish router, build-in templating, validators and zero-configuration features are suitable for small application and rapid development.

L<Amon2::Lite>

L<Mojolicious::Lite>

L<Dancer>

L<Kossy::Validator>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
