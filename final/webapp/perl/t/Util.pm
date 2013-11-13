package t::Util;

use strict;
use DBI;
use Test::mysqld;
use Test::More;
use Path::Tiny;
use JSON;
use Isucon3Final::Web;
use IO::Handle;
use LWP::UserAgent;
use File::Copy;
use Test::More();
use Exporter 'import';

our @EXPORT_OK = qw/ subtest_psgi /;
our $dsn;
our $mysqld;

$ENV{ISUCON_ENV} = "test";

sub subtest_psgi {
    my $name = shift;
    my @args = @_;
    Test::More::subtest $name, sub {
        main::test_psgi(@args);
    };
}

sub setup_mysql {
    $mysqld ||= Test::mysqld->new(
        my_cnf => {
            "skip-networking" => "",
        }
    ) or plan skip_all => $Test::mysqld::errstr;

    $dsn = $mysqld->dsn( dbname => "test" );
    my ($sock) = ( $dsn =~ m{mysql_socket=(.+?);} );
    note "socket=$sock";
    system("mysql -S $sock -u root test < ../config/schema.sql");
    return $dsn;
}

sub setup_webapp {
    use Plack::Builder;

    system("rm -fr t/tmp/");
    system("mkdir -p t/tmp/data/{icon,image}");
    File::Copy::copy("data/icon/default.png", "t/tmp/data/icon/default.png");

    if ($ENV{TARGET}) {
        override_to_real_server($ENV{TARGET});
        return;
    }
    my $root_dir = File::Basename::dirname(__FILE__) . "/..";
    my $dsn = setup_mysql();
    my $fh = path("$root_dir/../config/$ENV{ISUCON_ENV}.json")->openw;
    $fh->print(
        encode_json({
            database => { dsn => [ $dsn ] },
            data_dir => "t/tmp/data",
        }));
    $fh->close;

    my $app = Isucon3Final::Web->psgi($root_dir);
    builder {
        enable 'ReverseProxy';
        enable 'Static',
            path => qr!^/(?:(?:css|js|img)/|favicon\.ico$)!,
            root => $root_dir . '/t/tmp';
        $app;
    };
}

sub shutdown_db {
    undef $mysqld;
}

sub override_to_real_server {
    my $real_host = shift;
    my $ua        = LWP::UserAgent->new;
    $ua->agent("ISUCON Agent 2013");

    no warnings "redefine";
    my $test_psgi = sub {
        my %args = @_;
        my $cb = sub {
            my $req = shift;
            my $uri = $req->uri;
            my $orig_host = $uri->host;
            $uri->host($real_host);
            $req->uri($uri);
            $req->headers->header( Host => $orig_host );
            return $ua->request($req);
        };
        $args{client}->($cb);
    };
    *main::test_psgi = $test_psgi;
}

sub diff_pixels_percentage {
    my ($img, $other) = @_;

    my $w = $img->getwidth;
    my $h = $img->getheight;
    my $all = $w * $h;

    if ( my $method = $img->can('difference_pixels') ) {
        my $diff_pixels = $method->( $img, other => $other, mindist => 24 ) || 0;
        my $p = $diff_pixels / $all * 100;
        Test::More::note("$diff_pixels / $all = $p%");
        return $p;
    }

    my $diff = $img->difference(
        other   => $other,
        mindist => 24,
    ) or die $img->errstr;
    my $diff_pixels = 0;
    for my $y ( 0 .. $h - 1 ) {
        for my $c ( $diff->getscanline( y => $y ) ) {
            my (undef, undef, undef, $alpha) = $c->rgba();
            $diff_pixels++ if $alpha != 0;
        }
    }
    my $p = $diff_pixels / $all * 100;
    Test::More::note("$diff_pixels / $all = $p%");
    return $p;
}

1;
