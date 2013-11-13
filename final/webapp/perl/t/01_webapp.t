# -*- mode:perl -*-
use strict;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use t::Util qw/ subtest_psgi /;
use JSON;
use Test::Deep;
use Test::Deep::Matcher;
use Imager;
use Image::Size;

my $app = t::Util::setup_webapp();

subtest_psgi "/",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $res = $cb->(GET "http://localhost/");
        is $res->code => 200;
    };

subtest_psgi "signup no name",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $res = $cb->(
            POST "http://localhost/signup", [ name => "test-$$" ]
        );
        is $res->code => 400;
    };

subtest_psgi "signup name too short",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $res = $cb->(
            POST "http://localhost/signup", [ name => "t" ]
        );
        is $res->code => 400;
    };

subtest_psgi "signup name too long",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $res = $cb->(
            POST "http://localhost/signup", [ name => "t" x 17 ]
        );
        is $res->code => 400;
    };

subtest_psgi "signup, me",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_$$";
        my $res = $cb->(
            POST "http://localhost/signup", [ name => $name ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            id      => is_number,
            name    => $name,
            icon    => "http://localhost/icon/default",
            api_key => re('\A[0-9a-f]{64}\z'),
        };
        my $api_key = $r->{api_key};

        $res = $cb->(
            GET "http://localhost/me",
            X_API_Key => $api_key,
        );
        is $res->code => 200;
        $r = decode_json( $res->content );
        cmp_deeply $r => {
            id      => $r->{id},
            name    => $name,
            icon    => "http://localhost/icon/default",
        };
    };

subtest_psgi "icon not found",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_$$";
        my $res = $cb->( GET "http://localhost/icon/default_" );
        is $res->code => 404;
    };

subtest_psgi "default icon",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_$$";
        my $res = $cb->( GET "http://localhost/icon/default" );
        is $res->code => 200;
        is $res->content_type => "image/png";
        my $data = $res->content;
        my $img = Imager->new();
        $img->read( data => $data ) or die $img->errstr;
        is $img->getwidth  => 32;
        is $img->getheight => 32;
        my $compare = Imager->new;
        $compare->read( file => "t/data/icon/default_s.png" )
            or die $compare->errstr;
        my $p = t::Util::diff_pixels_percentage($img, $compare);
        ok $p <= 5.0;
    };

for my $size (qw/ s m l /) {
    my $sizemap = {
        s => 32,
        m => 64,
        l => 128,
    };
    subtest_psgi "default icon size $size",
        app    => $app,
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET "http://localhost/icon/default?size=$size" );
            is $res->code => 200;
            is $res->content_type => "image/png";
            my $data = $res->content;
            my $img = Imager->new();
            $img->read( data => $data ) or die $img->errstr;
            is $img->getwidth  => $sizemap->{$size};
            is $img->getheight => $sizemap->{$size};
            my $compare = Imager->new;
            $compare->read( file => "t/data/icon/default_$size.png" )
                or die $compare->errstr;
            my $p = t::Util::diff_pixels_percentage($img, $compare);
            ok $p <= 5.0;
        };
}

subtest_psgi "post icon (no api_key)",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $res = $cb->( POST "http://localhost/icon" );
        is $res->code => 400;
    };

subtest_psgi "post icon",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_icon_$$";
        my $res = $cb->(
            POST "http://localhost/signup", [ name => $name ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            id   => is_number,
            name => $name,
            icon => "http://localhost/icon/default",
            api_key => re('\A[0-9a-f]{64}\z'),
        };
        my $api_key = $r->{api_key};

        $res = $cb->(
            POST "http://localhost/icon",
                Content_Type => 'form-data',
                X_API_Key    => $api_key,
                Content      => [
                   image   => ["t/01_webapp.t"],
                ]
        );
        is $res->code => 400;

        $res = $cb->(
            POST "http://localhost/icon",
                Content_Type => 'form-data',
                X_API_Key    => $api_key,
                Content      => [
                   image   => ["t/data/icon/isucon.png"],
                ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            icon => re("http://localhost/icon/[a-zA-F0-9]{64}"),
        };
        my $icon_url = $r->{icon};
        for my $size ("", qw/ s m l /) {
            my $sizemap = {
                "" => 32,
                s  => 32,
                m  => 64,
                l  => 128,
            };
            my $url = $icon_url;
            $url .= "?size=$size" if $size;
            my $res = $cb->( GET $url );
            is $res->code => 200;
            is $res->content_type => "image/png";
            my $data = $res->content;
            my $img = Imager->new();
            $img->read( data => $data ) or die $img->errstr;
            is $img->getwidth  => $sizemap->{$size};
            is $img->getheight => $sizemap->{$size};
            my $compare = Imager->new;
            my $file = $size ? "t/data/icon/isucon_$size.png"
                             : "t/data/icon/isucon_s.png";
            $compare->read( file => $file )
                or die $compare->errstr;
            my $p = t::Util::diff_pixels_percentage($img, $compare);
            ok $p <= 5.0;
        }
    };


subtest_psgi "post entry publish_level=2",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_image_$$";
        my $res = $cb->(
            POST "http://localhost/signup", [ name => $name ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        my $api_key = $r->{api_key};

        my $file = "t/data/image/isucon.jpg";
        my ($original_w, $original_h) = imgsize($file);
        $res = $cb->(
            POST "http://localhost/entry",
                Content_Type => 'form-data',
                X_API_Key    => $api_key,
                Content      => [
                   image         => [ $file ],
                   publish_level => 2,
                ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            id            => is_number,
            image         => re("http://localhost/image/[a-zA-F0-9]{64}"),
            publish_level => 2,
            user => {
                id   => is_number,
                name => $name,
                icon => "http://localhost/icon/default",
            },
        };
        my $image_url = $r->{image};
        for my $size ("", qw/ s m l /) {
            my $sizemap = {
                "" => undef,
                s  => 128,
                m  => 256,
                l  => undef,
            };
            my $url = $image_url;
            $url .= "?size=$size" if $size;
            my $res = $cb->( GET $url );
            is $res->code => 200;
            is $res->content_type => "image/jpeg";
            my $data = $res->content;
            my $img = Imager->new();
            $img->read( data => $data ) or die $img->errstr;
            if ($sizemap->{$size}) {
                is $img->getwidth  => $sizemap->{$size};
                is $img->getheight => $sizemap->{$size};
            }
            else {
                is $img->getwidth  => $original_w;
                is $img->getheight => $original_h;
            }
            my $compare = Imager->new;
            my $file = $size ? "t/data/image/isucon_$size.jpg"
                             : "t/data/image/isucon.jpg";
            $compare->read( file => $file )
                or die $compare->errstr;
            my $p = t::Util::diff_pixels_percentage($img, $compare);
            ok $p <= 5.0;
        }
    };

subtest_psgi "post entry publish_level=0",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $name = "test_image_$$";
        my $res = $cb->(
            POST "http://localhost/signup", [ name => $name ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        my $api_key = $r->{api_key};

        my $file = "t/data/image/isucon.jpg";
        my ($original_w, $original_h) = imgsize($file);
        $res = $cb->(
            POST "http://localhost/entry",
                Content_Type => 'form-data',
                X_API_Key    => $api_key,
                Content      => [
                   image         => [ $file ],
                   publish_level => 0,
                ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            id            => is_number,
            image         => re("http://localhost/image/[a-zA-F0-9]{64}"),
            publish_level => 0,
            user => {
                id   => is_number,
                name => $name,
                icon => "http://localhost/icon/default",
            },
        };
        my $image_url = $r->{image};
        for my $size ("", qw/ s m l /) {
            my $url = $image_url;
            $url .= "?size=$size" if $size;
            my $res = $cb->( GET $url );
            is $res->code => 404;
        }
    };


subtest_psgi "post entry / delete",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $users = {};
        for my $n (1, 2) {
            my $name = "test_delete_$n";
            my $res = $cb->(
                POST "http://localhost/signup", [ name => $name ]
            );
            is $res->code => 200;
            my $r = decode_json( $res->content );
            $users->{$n} = $r;
        }
        my $file = "t/data/image/isucon.jpg";
        my $res = $cb->(
            POST "http://localhost/entry",
                Content_Type => 'form-data',
                X_API_Key    => $users->{1}->{api_key},
                Content      => [
                   image         => [ $file ],
                   publish_level => 2,
                ]
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            id            => is_number,
            image         => re("http://localhost/image/[a-zA-F0-9]{64}"),
            publish_level => 2,
            user => {
                id   => is_number,
                name => "test_delete_1",
                icon => "http://localhost/icon/default",
            },
        };
        my $image_url = $r->{image};
        my $entry_id  = $r->{id};

        $res = $cb->(GET $image_url);
        is $res->code => 200;

        $res = $cb->(
            POST "http://localhost/entry/$entry_id",
                X_API_Key    => $users->{2}->{api_key},
                Content      => [ __method => "DELETE" ],
        );
        is $res->code => 400;

        $res = $cb->(
            POST "http://localhost/entry/_$entry_id",
                X_API_Key    => $users->{2}->{api_key},
                Content      => [ __method => "DELETE" ],
        );
        is $res->code => 404;

        $res = $cb->(
            POST "http://localhost/entry/$entry_id",
                X_API_Key    => $users->{1}->{api_key},
                Content      => [ __method => "DELETE" ],
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => { ok => JSON::true };

        $res = $cb->(GET $image_url);
        is $res->code => 404;
    };


subtest_psgi "follow, unfollow",
    app    => $app,
    client => sub {
        my $cb  = shift;
        my $users = {};
        for my $n ( 1, 2, 3 ) {
            my $name = "test_follow_$n";
            my $res = $cb->(
                POST "http://localhost/signup", [ name => $name ]
            );
            is $res->code => 200;
            my $r = decode_json( $res->content );
            $users->{$n} = $r;
        }

        # 1 => 2, 3
        # 2 => 3
        my $res = $cb->(
            POST "http://localhost/follow", [ target => $users->{2}->{id} ],
            X_API_Key => $users->{1}->{api_key},
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            users => [{
                id   => $users->{2}->{id},
                name => "test_follow_2",
                icon => "http://localhost/icon/default",
            }]
        };

        $res = $cb->(
            POST "http://localhost/follow", [ target => $users->{3}->{id} ],
            X_API_Key => $users->{1}->{api_key},
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            users => [
                {
                    id   => $users->{2}->{id},
                    name => "test_follow_2",
                    icon => "http://localhost/icon/default",
                },
                {
                    id   => $users->{3}->{id},
                    name => "test_follow_3",
                    icon => "http://localhost/icon/default",
                }
            ]
        };
        $res = $cb->(
            GET "http://localhost/follow",
            X_API_Key => $users->{1}->{api_key},
        );
        my $r_ = decode_json( $res->content );
        cmp_deeply $r => $r_;

        $res = $cb->(
            POST "http://localhost/unfollow",
            [ target => $users->{2}->{id} ],
            X_API_Key => $users->{1}->{api_key},
        );
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            users => [
                {
                    id   => $users->{3}->{id},
                    name => "test_follow_3",
                    icon => "http://localhost/icon/default",
                },
            ]
        };
    };

subtest_psgi "follow publish_level=1 timeline",
    app    => $app,
    client => sub {
        my $cb  = shift;
        if ($ENV{TARGET}) {
            plan skip_all => 'TARGET mode';
        }
        $Isucon3Final::Web::TIMEOUT = 1;

        my $users = {};
        for my $n ( 1, 2, 3 ) {
            my $name = "test_$n";
            my $res = $cb->(
                POST "http://localhost/signup", [ name => $name ]
            );
            is $res->code => 200;
            my $r = decode_json( $res->content );
            $users->{$n} = $r;
        }

        # 1 => 2, 3
        # 2 => 3
        my $res = $cb->(
            POST "http://localhost/follow", [
                target => $users->{2}->{id},
                target => $users->{3}->{id},
            ],
            X_API_Key => $users->{1}->{api_key},
        );
        $res = $cb->(
            POST "http://localhost/follow", [
                target => $users->{3}->{id},
            ],
            X_API_Key => $users->{2}->{api_key},
        );

        my $poster_viewer_code = {
            1 => { 1 => 200, 2 => 404, 3 => 404 },
            2 => { 1 => 200, 2 => 200, 3 => 404 },
            3 => { 1 => 200, 2 => 200, 3 => 200 },
        };
        for my $poster (sort keys %$poster_viewer_code) {
            my $file = "t/data/image/isucon.jpg";
            $res = $cb->(
                POST "http://localhost/entry",
                    Content_Type => 'form-data',
                    X_API_Key    => $users->{$poster}->{api_key},
                    Content      => [
                       image         => [ $file ],
                       publish_level => 1,
                    ]
                );
            is $res->code => 200;
            my $r = decode_json( $res->content );
            my $image_url = $r->{image};
            for my $viewer (sort keys %{ $poster_viewer_code->{$poster} }) {
                my $code = $poster_viewer_code->{$poster}->{$viewer};
                is $cb->(GET $image_url, X_API_Key => $users->{$viewer}->{api_key})->code => $code, "poster:$poster viewer:$viewer code:$code";
            }
        }

        # timeline
        $res = $cb->(
            GET "http://localhost/timeline",
            X_API_Key => $users->{2}->{api_key},
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        cmp_deeply $r => {
            latest_entry => is_number,
            entries => [
                {
                    id    => is_number,
                    image => re('^http://localhost/image/[0-9a-f]{64}$'),
                    publish_level => 1,
                    user  => {
                        id   => is_number,
                        name => "test_3",
                        icon => "http://localhost/icon/default",
                    }
                },
                {
                    id    => is_number,
                    image => re('^http://localhost/image/[0-9a-f]{64}$'),
                    publish_level => 1,
                    user  => {
                        id   => is_number,
                        name => "test_2",
                        icon => "http://localhost/icon/default",
                    }
                },
                {
                    id    => is_number,
                    image => re('^http://localhost/image/[0-9a-f]{64}$'),
                    publish_level => 2,
                    user  => {
                        id   => is_number,
                        name => is_string,
                        icon => "http://localhost/icon/default",
                    }
                },
            ],
        };
        my $latest_entry = $r->{latest_entry};
        $res = $cb->(
            GET "http://localhost/timeline?latest_entry=$latest_entry",
            X_API_Key => $users->{2}->{api_key},
        );
        is $res->code => 200;
        my $r = decode_json( $res->content );
        note explain $r;
        cmp_deeply $r => {
            latest_entry => $latest_entry,
            entries => []
        };

        my $file = "t/data/image/isucon.jpg";
        my $entries = {};
        for my $n (1, 3) {
            $res = $cb->(
                POST "http://localhost/entry",
                Content_Type => 'form-data',
                X_API_Key    => $users->{$n}->{api_key},
                Content      => [
                    image         => [ $file ],
                    publish_level => 1,
                ]
            );
            $entries->{$n} = decode_json($res->content);
        }

        $res = $cb->(
            GET "http://localhost/timeline?latest_entry=$latest_entry",
            X_API_Key => $users->{2}->{api_key},
        );
        is $res->code => 200;
        $r = decode_json( $res->content );
        note explain $r;
        cmp_deeply $r => {
            latest_entry => $entries->{3}->{id},
            entries => [ $entries->{3} ]
        };
    };



done_testing;
