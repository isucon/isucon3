package Isucon2013Final::Bench;
use 5.12.0;
use strict;
use warnings;
use Furl;
use HTTP::Request::Common;
use Parallel::Benchmark;
use Isucon2013Final::Bench::DictWords qw/ random_word /;
use JSON;
use Mouse;
use Clone qw/ clone /;
use Path::Tiny;
use Log::Minimal;
use Try::Tiny;
use Time::HiRes qw/ gettimeofday tv_interval sleep time /;
use POSIX qw/ SIGTERM SIGINT /;
use Sub::Rate;
use Digest::SHA qw/ sha256_hex /;
use List::Util qw/ first shuffle /;
use Imager;
use Image::Size;
use AnyEvent::HTTP;
use Carp;
use constant {
    HTTP_DEFAULT_TIMEOUT         => 5,
    HTTP_LONGPOLL_TIMEOUT        => 35,
    USERS                        => 100,
    ENTRIES                      => 50 - 3,
    PUBLISH_LEVEL_PUBLIC         => 2,
    PUBLISH_LEVEL_FOLLOWERS_ONLY => 1,
    PUBLISH_LEVEL_PRIVATE        => 0,
    USER_AGENT                   => "ISUCON Agent 2013",
    SCORE_POST_ENTRY             => 10,
    SCORE_TIMELINE_REFLECTION    => 10,
    SCORE_ICON                   => 0.1,
    SCORE_DEFAULT                => 1,
    TIMELINE_REFLECTION_LIMIT    => 20,
    IMAGE_DIFF_PERCENTAGE_LIMIT  => 5,
    ICON_DIFF_PERCENTAGE_LIMIT   => 20,
    TIMELINE_MAX_ENTRIES         => 30,
    MAX_ERRORS                   => 5,
};

our @Icon;
our @Image;

sub source_dir {
    my $class = shift;
    my $dir   = shift;
    my $source_dir = path($dir);
    @Icon  = grep { $_->basename =~ /\.png$/ && $_->basename !~ /_[sml]\.png$/ } $source_dir->children;
    @Image = grep { $_->basename =~ /\.jpg$/ && $_->basename !~ /_[sml]\.jpg$/ } $source_dir->children;
}

has endpoint => (
    is => "rw",
);

has icon_dir => (
    is => "rw",
);

has ua => (
    is => "rw",
    default => \&_new_ua,
);

has result => (
    is => "rw",
    default => sub {
        +{
            success => 0,
            fail    => 0,
        }
    },
);

has timeout => (
    is      => "rw",
    isa     => "Int",
    default => 60,
);

has start => (
    is => "rw",
);

has latest_entry => (
    is => "rw",
);

has host => (
    is => "rw",
);

my $ImageSizeRate = do {
    my $rate = Sub::Rate->new( max_rate => 100 );
    $rate->add( 10 => sub { "" } );
    $rate->add( 25 => sub { "?size=m" } );
    $rate->add( default => sub { undef });
    $rate->generate;
};

my $ViewingImageSizeRate = do {
    my $rate = Sub::Rate->new( max_rate => 100 );
    $rate->add( 60 => sub { "?size=s" } );
    $rate->add( 25 => sub { "?size=m" } );
    $rate->add( default => sub { "?size=l" });
    $rate->generate;
};

my $PublishLevelRate = do {
    my $rate = Sub::Rate->new( max_rate => 100 );
    $rate->add( 5       => sub { PUBLISH_LEVEL_PUBLIC         } );
    $rate->add( 70      => sub { PUBLISH_LEVEL_FOLLOWERS_ONLY } );
    $rate->add( default => sub { PUBLISH_LEVEL_PRIVATE        } );
    $rate->generate;
};

my $IconSizeRate = do {
    my $rate = Sub::Rate->new( max_rate => 100 );
    $rate->add( 80 => sub { "" } );
    $rate->add( 17 => sub { "?size=m" } );
    $rate->add( 3  => sub { "?size=l" });
    $rate->generate;
};

sub calc_SCORE_POST_ENTRY {
    my $elapsed = shift;
    my $s = log( SCORE_POST_ENTRY / $elapsed ) / log(2);
    debugf "post /entry score %.2f elapsed %.3f", $s, $elapsed;
    return $s;
}

sub calc_SCORE_TIMELINE_REFLECTION {
    my $elapsed = shift;
    my $s = log( SCORE_POST_ENTRY / $elapsed ) / log(2);
    debugf "timeline score %.2f elapsed %.3f", $s, $elapsed;
    return $s;
}

sub valid_uri {
    my ($self, $uri) = @_;
    state $host = $self->endpoint->host;
    state $port = $self->endpoint->port;
    my $u = URI->new($uri);
    if ( $u->host ne $self->host ) {
        critf("invalid uri $u");
        exit(1);
    }
    $u->host($host);
    $u->port($port) if $port != 80 || $port != 443;
    $u;
}

sub diff_pixels_percentage {
    my ($img, $other) = @_;

    my $w = $img->getwidth;
    my $h = $img->getheight;
    my $all = $w * $h;

    if ( my $method = $img->can('difference_pixels') ) {
        my $diff_pixels = $method->( $img, other => $other, mindist => 24 ) || 0;
        my $p = $diff_pixels / $all * 100;
        debugf("$diff_pixels / $all = $p%");
        return $p;
    }

    my $diff = $img->difference(
        other   => $other,
        mindist => 24,
    ) or die "Can't load image " . $img->errstr;
    my $diff_pixels = 0;
    for my $y ( 0 .. $h - 1 ) {
        for my $c ( $diff->getscanline( y => $y ) ) {
            my (undef, undef, undef, $alpha) = $c->rgba();
            $diff_pixels++ if $alpha != 0;
        }
    }
    my $p = $diff_pixels / $all * 100;
    debugf("$diff_pixels / $all = $p%");
    return $p;
}

sub _new_ua {
    Furl->new(
        agent   => USER_AGENT,
        timeout => HTTP_DEFAULT_TIMEOUT,
    );
}

sub reset_ua {
    my $self = shift;
    return if rand() > 0.3;
    $self->ua( _new_ua );
}

sub adjust_timeout {
    my $self    = shift;
    my $timeout = shift;
    my $ignore_timeout;

    my $elapsed = tv_interval($self->start);
    if ( $elapsed >= $self->timeout ) {
        die "timeout";
    }
    my $remaining = $self->timeout - $elapsed;
    if ( $timeout == HTTP_LONGPOLL_TIMEOUT && $remaining < $timeout ) {
        $timeout = int($remaining);
        debugf "adjust timeout %d", $remaining;
        $ignore_timeout = 1;
    }
    return $timeout, $ignore_timeout;
}

sub request {
    my $self = shift;
    my $req  = shift;
    my $args = shift || {};

    my ($timeout, $ignore_timeout)
        = $self->adjust_timeout($args->{timeout} // HTTP_DEFAULT_TIMEOUT);
    ${$self->ua}->{timeout} = $timeout;

    my $endpoint = $self->endpoint;
    my $uri = clone($self->endpoint);

    $uri->path_query($req->uri->path_query);
    $req->uri($uri);
    $req->header("Host" => $self->host);
    debugf "%s %s", $req->method, $req->uri;
    my $start = [ gettimeofday ];
    my $res = $self->ua->request($req);
    my $elapsed = tv_interval($start);
    my $body;
    if ( $res->is_success || $args->{raw} ) {
        my $path = $req->uri->path;
        $self->result->{success}
            += ($req->method eq "POST" && $path eq "/entry") ? calc_SCORE_POST_ENTRY($elapsed)
             : ($path =~ m{/icon/})                          ? SCORE_ICON
             :                                                 SCORE_DEFAULT;
        if ( $res->content_type =~ m/^application\/json/ ) {
            $body = decode_json($res->content);
        }
        else {
            $body = $res->content;
        }
    } elsif (!$ignore_timeout) {
        critf "status: %s", $res->status_line;
        critf "%s %s", $req->method, $req->uri;
        critf "request %s failed %s", $req->uri, $res->status_line;
        exit 1;
    }
    return ($res, $body);
}

sub is {
    my ($got, $expected, $title) = @_;
    if ( $got ne $expected ) {
        critf "$title failed got: $got expected: $expected";
        exit(1);
    }
}

sub maybe {
    my ($got, $expected, $title) = @_;
    state @errors;
    if ( $got ne $expected ) {
        push @errors, "$title failed got: $got expected: $expected";
    }
    if (@errors > MAX_ERRORS) {
        critf "Too many errors found.";
        critf $_ for @errors;
        exit(1);
    }
}

sub ok {
    my ($expr, $title) = @_;
    if ( !$expr ) {
        critf "$title failed";
        exit(1);
    }
}

sub maybe_ok {
    my ($expr, $title) = @_;
    state @errors;
    if ( !$expr ) {
        push @errors, "$title failed";
    }
    if (@errors > MAX_ERRORS) {
        critf "Too many errors found.";
        critf $_ for @errors;
        exit(1);
    }
}

sub pickup_icon {
    $Icon[ int rand(scalar @Icon) ];
}

sub pickup_image {
    $Image[ int rand(scalar @Image) ];
}

sub pickup_user_image_serial {
    my ($level) = shift || 0;
    int(rand(ENTRIES - 3) / 3) * 3 + 3 + $level;
}

sub pickup_user_serial {
    int( rand(USERS - 1) ) + 1;
}

sub pickup_no_one_following_user_serial {
    int(rand(USERS - 13) / 13) * 13 + 13;
}

sub api_key {
    my $user_serial = shift;
    sha256_hex("api_key_${user_serial}");
}

sub image_id {
    my ($user_serial, $image_serial) = @_;
    sha256_hex("image_${user_serial}_${image_serial}");
}

sub BUILD {
    my $self = shift;

    my $fh = path('/dev/urandom')->openr;
    my $buf;
    $fh->read($buf, 4);
    $fh->close;
    srand(vec($buf, 0, 32));

    $self->start([ gettimeofday ]);
}

sub run {
    my $self = shift;
    my $method = shift;
    $self->result->{success} = 0;
    try {
        $self->$method();
    }
    catch {
        my $e = $_;
        croak($e) if $e !~ /^timeout/;
    };
    $self->result->{success};
}

sub post_get_delete_get {
    my $self = shift;
    my $user_serial = pickup_user_serial;
    my $api_key = api_key($user_serial);

    my $image = pickup_image();
    my ($res, $r) = $self->request(
        POST "/entry",
        Content_Type => 'form-data',
        X_API_Key    => $api_key,
        Content      => [
            image         => [ $image ],
            publish_level => PUBLISH_LEVEL_PUBLIC,
        ]
    );
    my $entry_id  = $r->{id};
    my $image_url = $r->{image};
    ($res, $r) = $self->request(
        GET $image_url,
    );
    ($res, $r) = $self->request(
        POST "/entry/$entry_id",
        X_API_Key    => $api_key,
        Content      => [
            __method => "DELETE",
        ]
    );
    ok $r->{ok}, "delete ok";
    ($res, $r) = $self->request(
        GET($image_url),
        { raw => 1 },
    );
    is $res->code => 404, "$image_url must be 404 got " . $res->code;
}

sub post {
    my $self = shift;
    my $user_serial = pickup_user_serial;
    my $api_key = api_key($user_serial);

    {
        my $icon_file = pickup_icon();
        my ($res, $r) = $self->request(
            POST "/icon",
            Content_Type => 'form-data',
            X_API_Key    => $api_key,
            Content      => [
                image => [ "$icon_file" ],
            ]
        );
        my $icon = $self->valid_uri($r->{icon});
        ($res, $r) = $self->request(
            GET $icon->as_string,
            X_API_Key => $api_key,
        );
        my $img = Imager->new;
        $img->read( data => $r )
            or die "Can't read image " . $img->errstr;
        is $img->getwidth  => 32, "icon width";
        is $img->getheight => 32, "icon height";

        my $compare = Imager->new;
        (my $compare_file = $icon_file) =~ s{/?([^/]+\.png)$}{/s/$1};
        $compare->read( file => $compare_file );
        debugf "comparing $icon $compare_file";
        my $p = diff_pixels_percentage($img, $compare);
        if ( $p > ICON_DIFF_PERCENTAGE_LIMIT ) {
            critf "icon diff > %d%% %s", ICON_DIFF_PERCENTAGE_LIMIT, $icon->as_string;
            exit(1);
        }
    }

    my $image = pickup_image();
    my $level = $PublishLevelRate->();
    my ($res, $r) = $self->request(
        POST "/entry",
        Content_Type => 'form-data',
        X_API_Key    => $api_key,
        Content      => [
            image         => [ $image ],
            publish_level => $level,
        ]
    );
    my ($original_w, $original_h) = imgsize("$image");
    for my $size ("", shuffle(qw/ s m l /)) {
        my $sizemap = {
            "" => undef,
            s  => 128,
            m  => 256,
            l  => undef,
        };
        my $image_url = $r->{image};
        $image_url .= "?size=$size" if $size;
        my ($res, $body) = $self->request(
            GET $image_url,
            X_API_Key => $api_key,
        );
        my $img = Imager->new();
        $img->read( data => $body )
            or die "Can't read image " . $img->errstr;
        if ($sizemap->{$size}) {
            is $img->getwidth  => $sizemap->{$size}, "width";
            is $img->getheight => $sizemap->{$size}, "height";
        }
        else {
            is $img->getwidth  => $original_w, "width";
            is $img->getheight => $original_h, "height";
        }
        my $compare_file;
        if ($size && ($size eq "m" || $size eq "s") ) {
            $compare_file = $image;
            $compare_file =~ s{/([^/]+\.(?:jpg|png)$)}{/$size/$1};
        }
        else {
            $compare_file = $image;
        }
        my $compare = Imager->new;
        debugf "comparing $image_url $compare_file";
        $compare->read( file => $compare_file )
            or die "can't read $compare_file. " . $compare->errstr;
        my $p = diff_pixels_percentage($img, $compare);
        if ( $p > IMAGE_DIFF_PERCENTAGE_LIMIT ) {
            critf "image diff > %s%% %s", IMAGE_DIFF_PERCENTAGE_LIMIT, $image_url;
            exit(1);
        }
    }
    sleep 1;
}

sub view {
    my $self = shift;
    my $user_serial = pickup_user_serial;
    my $api_key     = api_key($user_serial);

    my $user_image_serial = pickup_user_image_serial( $PublishLevelRate->() );
    my $image = image_id($user_serial, $user_image_serial);
    my ($res, $r) = $self->request(
        GET "/image/$image" . $ViewingImageSizeRate->(),
        X_API_Key => $api_key,
    );
    sleep 0.5;
}

sub timeline {
    my $self = shift;

    my $user_serial = pickup_user_serial;
    my $api_key = shift || api_key($user_serial);
    $self->latest_entry(undef);

    my $r_headers = {
        "X-API-Key"  => $api_key,
        "User-Agent" => USER_AGENT,
        Host         => $self->host,
        Referer      => undef,
    };
    my $cv = AE::cv;
    my ($start, $posted_entry_image, $posted_entry_id);

    my $get_timeline = sub {
        my $url  = clone($self->endpoint);
        my $path = "/timeline";

        my $latest_entry = 0;
        if ($self->latest_entry) {
            $path .= "?latest_entry=" . $self->latest_entry;
            $latest_entry = $self->latest_entry;
        }

        $url->path_query($path);
        my ($timeout, $ignore_timeout)
            = $self->adjust_timeout(HTTP_LONGPOLL_TIMEOUT);
        http_get $url,
            timeout => $timeout,
            headers => $r_headers,
            sub {
                my ($body, $h) = @_;
                my $elapsed = tv_interval($start);
                my $status = $h->{Status};
                if ($ignore_timeout && $status >= 590) {
                    $cv->send($elapsed);
                    return;
                }
                maybe $status => 200, "$path status";

                if ( $h->{"content-type"} =~ /^application\/json/ ) {
                    $body = decode_json($body);
                }
                if (!$self->latest_entry) {
                    maybe scalar @{ $body->{entries} } => TIMELINE_MAX_ENTRIES, "timeline entries short";
                }
                my $host = $self->host;
                for my $e (@{ $body->{entries} }) {
                    my $image = $self->valid_uri($e->{image} . "?size=s");
                    my $icon  = $self->valid_uri($e->{user}->{icon} . $IconSizeRate->());
                    if ( rand() > 0.8 && $user_serial && $user_serial % 13 != 0 ) {
                        my $follow_url = clone($self->endpoint);
                        $follow_url->path("/follow");
                        http_post $follow_url, "target=" . $e->{user}->{id},
                            timeout => HTTP_DEFAULT_TIMEOUT,
                            headers => {
                                %$r_headers,
                                "Content-Type" => "application/x-www-form-urlencoded",
                            },
                            sub {
                                my (undef, $h) = @_;
                                maybe $h->{Status} => 200, "/follow must be 200 got $h->{Status}";
                                $self->result->{success} += SCORE_DEFAULT;
                            };
                    }
                    http_get $image,
                        timeout => HTTP_DEFAULT_TIMEOUT,
                        headers => $r_headers,
                        sub {
                            my (undef, $h) = @_;
                            maybe $h->{Status} => 200, "$image status";
                            $self->result->{success} += SCORE_DEFAULT;
                        };
                    http_get $icon,
                        timeout => HTTP_DEFAULT_TIMEOUT,
                        headers => $r_headers,
                        sub {
                            my ($body, $h) = @_;
                            maybe $h->{Status} => 200, "$icon status";
                            maybe_ok length($body) > 0, "$icon bytes > 0";
                            $self->result->{success} += SCORE_ICON;
                        };
                    my $size = $ImageSizeRate->();
                    if (defined $size) {
                        my $x_image = $self->valid_uri($e->{image} . $size);
                        http_get $x_image,
                            timeout => HTTP_DEFAULT_TIMEOUT,
                            headers => $r_headers,
                            sub {
                                my (undef, $h) = @_;
                                maybe $h->{Status} => 200, "$x_image status";
                                $self->result->{success} += SCORE_DEFAULT;
                            };
                    }

                }
                no warnings;
                maybe_ok $latest_entry <= $body->{latest_entry}, "latest_entry updated";
                $self->latest_entry($posted_entry_id || $body->{latest_entry});

                if (!$posted_entry_image) {
                    # 待ち受け状態じゃない場合はチェックしないでかえる
                    $cv->send(-1);
                    return;
                }
                my ($e) = grep { $_->{image} eq $posted_entry_image }
                    @{ $body->{entries} };
                if ($e) {
                    debugf ddf $e;
                    $self->result->{success}
                        += calc_SCORE_TIMELINE_REFLECTION($elapsed);
                    $cv->send($elapsed);
                } else {
                    debugf "posted entry is not found in timeline";
                    $cv->send(-1);
                }
            };
    };
    $get_timeline->();

    my $w = AE::timer rand(), 0, sub {
        my $level = $PublishLevelRate->();
        my $post_url = clone($self->endpoint);
        $post_url->path("/entry");
        my $req = POST $post_url->as_string,
            Content_Type => 'form-data',
                X_API_Key    => $api_key,
                Content      => [
                    image         => [ pickup_image() ],
                    publish_level => $level,
                ];
        my $post_start;
        http_post $post_url, $req->content,
            timeout => HTTP_DEFAULT_TIMEOUT,
            on_prepare => sub { $post_start = [ gettimeofday ] },
            headers => {
                "Content-Type"   => $req->header("Content-Type"),
                "Content-Length" => $req->header("Content-Length"),
                %$r_headers,
            },
            sub {
                my ($body, $h) = @_;
                my $status = $h->{Status};
                maybe $status => 200, "POST /entry status";
                if ( $h->{"content-type"} =~ /^application\/json/ ) {
                    $body = decode_json($body);
                }
                $self->result->{success}
                    += calc_SCORE_POST_ENTRY(tv_interval($post_start));
                $posted_entry_image = $body->{image};
                $self->latest_entry($body->{id} - 1);
                $posted_entry_id = $body->{id} - 1;
                $start = [ gettimeofday ];
                debugf "posted_entry_image: %s", $posted_entry_image;
            };
    };

    my $w2 = AE::timer TIMELINE_REFLECTION_LIMIT + 1, 0, sub {
        critf "timeline reflection timeout";
        exit(1);
    };

    my $elapsed;
    while (1) {
        $elapsed = $cv->recv;
        last if $elapsed != -1;
        $cv = AE::cv;
        $get_timeline->();
    }
    undef $w2; # timer cancel

    if ($elapsed > TIMELINE_REFLECTION_LIMIT) {
        critf "timeline reflection timeout %.2f", $elapsed;
        exit(1);
    }

    debugf "%s timeline elapsed %.3f", $self->latest_entry, $elapsed;
}

sub check {
    my $self = shift;
    my $user_serial = pickup_user_serial;
    my $api_key     = api_key($user_serial);

    for my $level ( PUBLISH_LEVEL_PUBLIC, PUBLISH_LEVEL_FOLLOWERS_ONLY, PUBLISH_LEVEL_PRIVATE ) {
        # 自分は全部見える
        my $user_image_serial = pickup_user_image_serial($level);
        my $image = image_id($user_serial, $user_image_serial);
        my ($res, $r) = $self->request(
            GET "/image/$image" . $ViewingImageSizeRate->(),
            X_API_Key => $api_key,
        );
        sleep 0.1;
    }
    {
        # private なのは api_key なしでは 404 になるはず
        my $user_image_serial = pickup_user_image_serial(PUBLISH_LEVEL_PRIVATE);
        my $image = image_id($user_serial, $user_image_serial);
        my ($res, $r) = $self->request(
            GET("/image/$image" . $ViewingImageSizeRate->()),
            { raw => 1 },
        );
        is $res->code => 404, "/image/$image must be 404 got " . $res->code;
        sleep 0.1;
    }
    {
        # followしているユーザの followers_only な画像が見える
        my ($res, $r) = $self->request(
            GET "/follow", X_API_Key => $api_key,
        );
        my $f_user = first { $_->{id} < USERS } shuffle @{ $r->{users} };
        return unless $f_user; # 誰もフォローしていない

        my $uid = $f_user->{id};
        my $user_image_serial = pickup_user_image_serial(PUBLISH_LEVEL_FOLLOWERS_ONLY);
        my $image = image_id($uid, $user_image_serial);
        ($res, $r) = $self->request(
            GET "/image/$image" . $ViewingImageSizeRate->(),
            X_API_Key => $api_key,
        );
        sleep 0.1;
        # api_key を指定しないと404になる
        ($res, $r) = $self->request(
            GET("/image/$image" . $ViewingImageSizeRate->()),
            { raw => 1 },
        );
        is $res->code => 404, "/image/$image must be 404 got " . $res->code;
        sleep 0.1;

        # だれもフォローしてないユーザで見ると404になるはず
        my $nf_uid = pickup_no_one_following_user_serial;
        my $x_api_key = api_key($nf_uid);
        ($res, $r) = $self->request(
            GET "/follow",
            X_API_KEY => $x_api_key,
        );
        return if @{ $r->{users} } != 0; # フォローしちゃってたら抜ける

        ($res, $r) = $self->request(
            GET("/image/$image" . $ViewingImageSizeRate->(),
                X_API_KEY => $x_api_key,
            ),
            { raw => 1 },
        );
        if ( $uid == $nf_uid ) { # 自分の場合は200
            is $res->code => 200, "/image/$image must be 200 got " . $res->code;
        } else {
            is $res->code => 404, "/image/$image must be 404 got " . $res->code;
        }
        sleep 0.1;
    }
}

sub crawl {
    my $self = shift;

    my $api_key = do {
        $self->request(GET "/");
        my ($res, $r) = $self->request(
            POST "/signup", [ name => random_word() ]
        );
        $r->{api_key};
    };
    {
        my ($res, $r) = $self->request(
            GET "/me",
            X_API_Key => $api_key,
        );
        my $icon = $self->valid_uri($r->{icon});
        $self->request(
            GET $icon->as_string,
            X_API_Key => $api_key,
        );
    }
    {
        my ($res, $r) = $self->request(
            POST "/icon",
            Content_Type => 'form-data',
            X_API_Key    => $api_key,
            Content      => [
                image => [ pickup_icon() ],
            ]
        );
        my $icon = $self->valid_uri($r->{icon} . $IconSizeRate->());
        $self->request(
            GET $icon->as_string,
            X_API_Key => $api_key,
        );
    }
    $self->timeline($api_key);
}

1;

