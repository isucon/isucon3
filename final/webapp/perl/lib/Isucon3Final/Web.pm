package Isucon3Final::Web;

use strict;
use warnings;
use utf8;
use Kossy;
use Digest::SHA qw/ sha256_hex /;
use DBIx::Sunny;
use JSON;
use JSON::Types;
use File::Temp qw/ tempfile /;
use POSIX qw/ floor /;
use File::Copy;
use Data::UUID;

our $TIMEOUT  = 30;
our $INTERVAL = 2;
our $UUID     = Data::UUID->new;

use constant {
    ICON_S   => 32,
    ICON_M   => 64,
    ICON_L   => 128,
    IMAGE_S  => 128,
    IMAGE_M  => 256,
    IMAGE_L  => undef,
};

sub convert {
    my $self = shift;
    my ($orig, $ext, $w, $h) = @_;
    my ($fh, $filename) = tempfile();
    my $newfile = "$filename.$ext";
    system("convert", "-geometry", "${w}x${h}", $orig, $newfile);
    open my $newfh, "<", $newfile or die $!;
    read $newfh, my $data, -s $newfile;
    close $newfh;
    unlink $newfile;
    unlink $filename;
    $data;
}

sub crop_square {
    my $self = shift;
    my ($orig, $ext) = @_;
    my $identity = `identify $orig`;
    my (undef, undef, $size) = split / +/, $identity;
    my ($w, $h) = split /x/, $size;
    my ($crop_x, $crop_y, $pixels);
    if ( $w > $h ) {
        $pixels = $h;
        $crop_x = floor(($w - $pixels) / 2);
        $crop_y = 0;
    }
    elsif ( $w < $h ) {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = floor(($h - $pixels) / 2);
    }
    else {
        $pixels = $w;
        $crop_x = 0;
        $crop_y = 0;
    }
    my ($fh, $filename) = tempfile();
    system("convert", "-crop", "${pixels}x${pixels}+${crop_x}+${crop_y}", $orig, "$filename.$ext");
    unlink $filename;
    return "$filename.$ext";
}

sub load_config {
    my $self = shift;
    $self->{_config} ||= do {
        my $env = $ENV{ISUCON_ENV} || 'local';
        open(my $fh, '<', $self->root_dir . "/../config/${env}.json") or die $!;
        my $json = do { local $/; <$fh> };
        close($fh);
        decode_json($json);
    };
}

sub dbh {
    my ($self) = @_;
    $self->{_dbh} ||= do {
        my $dbconf = $self->load_config->{database};
        my @dsn = $dbconf->{dsn}
                ? @{ $dbconf->{dsn} }
                : (
                    "dbi:mysql:database=${$dbconf}{dbname};host=${$dbconf}{host};port=${$dbconf}{port}",
                    $dbconf->{username},
                    $dbconf->{password},
                );
        DBIx::Sunny->connect(
            @dsn, {
                RaiseError           => 1,
                PrintError           => 0,
                AutoInactiveDestroy  => 1,
                mysql_enable_utf8    => 1,
                mysql_auto_reconnect => 1,
            }
        );
    };
}

filter 'require_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        if (! $c->stash->{user}) {
            $c->halt(400);
        }
        $app->($self, $c);
    };
};

filter 'get_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        my $api_key = $c->req->headers->header("X-API-Key")
                   || $c->req->cookies->{api_key}
        ;
        my $user = $self->dbh->select_row(
            'SELECT * FROM users WHERE api_key=?',
            $api_key,
        );
        $c->stash->{user} = $user;
        $app->($self, $c);
    };
};

get '/' => sub {
    my ( $self, $c )  = @_;
    open my $fh, "<", "./public/index.html";
    my $html = do { local $/; <$fh> };
    $c->res->body($html);
};

post '/signup' => sub {
    my ( $self, $c ) = @_;
    my $name = $c->req->param("name");
    if ( $name !~ /\A[0-9a-zA-Z_]{2,16}\z/ ) {
        $c->halt(400);
    }
    my $api_key = sha256_hex( $UUID->create );
    $self->dbh->query(
        'INSERT INTO users (name, api_key, icon) VALUES (?, ?, ?)',
        $name, $api_key, 'default',
    );
    my $id = $self->dbh->last_insert_id;
    my $user = $self->dbh->select_row(
        'SELECT * FROM users WHERE id=?', $id,
    );
    $c->render_json({
        id      => number $user->{id},
        name    => string $user->{name},
        icon    => string $c->req->uri_for("/icon/" . $user->{icon}),
        api_key => string $user->{api_key},
    });
};

get '/me' => [qw/ get_user require_user/] => sub {
    my ( $self, $c ) = @_;
    my $user = $c->stash->{user};
    $c->render_json({
        id   => number $user->{id},
        name => string $user->{name},
        icon => string $c->req->uri_for("/icon/" . $user->{icon}),
    });
};

get '/icon/:icon' => sub {
    my ( $self, $c ) = @_;
    my $icon = $c->args->{icon};
    my $size = $c->req->param("size") || "s";
    my $dir  = $self->load_config->{data_dir};
    if ( ! -e "$dir/icon/${icon}.png" ) {
        $c->halt(404);
    }
    my $w = $size eq "s" ? ICON_S
          : $size eq "m" ? ICON_M
          : $size eq "l" ? ICON_L
          :                ICON_S;
    my $h = $w;

    my $data = $self->convert("$dir/icon/${icon}.png", "png", $w, $h);
    $c->res->content_type("image/png");
    $c->res->content( $data );
    $c->res;
};

post '/icon' => [qw/ get_user require_user /] => sub {
    my ( $self, $c ) = @_;
    my $user   = $c->stash->{user};
    my $upload = $c->req->uploads->{image};
    if (!$upload) {
        $c->halt(400);
    }
    if ( $upload->content_type !~ /^image\/(jpe?g|png)$/ ) {
        $c->halt(400);
    }
    my $file = $self->crop_square($upload->path, "png");
    my $icon = sha256_hex( $UUID->create );
    my $dir  = $self->load_config->{data_dir};
    File::Copy::move($file, "$dir/icon/$icon.png")
        or $c->halt(500);

    $self->dbh->query(
        'UPDATE users SET icon=? WHERE id=?',
        $icon, $user->{id},
    );
    $c->render_json({
        icon => string $c->req->uri_for("/icon/" . $icon),
    });
};

post '/entry' => [qw/ get_user require_user /] => sub {
    my ($self, $c) = @_;
    my $user   = $c->stash->{user};
    my $upload = $c->req->uploads->{image};
    if (!$upload) {
        $c->halt(400);
    }
    my $content_type = $upload->content_type;
    if ($content_type !~ /^image\/jpe?g/) {
        $c->halt(400);
    }
    my $image_id = sha256_hex( $UUID->create );
    my $dir = $self->load_config->{data_dir};
    File::Copy::move($upload->path, "$dir/image/$image_id.jpg")
        or $c->halt(500);

    my $publish_level = $c->req->param("publish_level");
    $self->dbh->query(
        'INSERT INTO entries (user, image, publish_level, created_at) VALUES (?, ?, ?, now())',
        $user->{id}, $image_id, $publish_level,
    );
    my $id = $self->dbh->last_insert_id;
    my $entry = $self->dbh->select_row(
        'SELECT * FROM entries WHERE id=?', $id,
    );
    $c->render_json({
        id            => number $entry->{id},
        image         => string $c->req->uri_for("/image/" . $entry->{image}),
        publish_level => number $entry->{publish_level},
        user => {
            id   => number $user->{id},
            name => string $user->{name},
            icon => string $c->req->uri_for("/icon/" . $user->{icon}),
        },
    });
};

post '/entry/:id' => [qw/ get_user require_user /] => sub {
    my ( $self, $c ) = @_;
    my $user  = $c->stash->{user};
    my $id    = $c->args->{id};
    my $dir   = $self->load_config->{data_dir};
    my $entry = $self->dbh->select_row("SELECT * FROM entries WHERE id=?", $id);
    if ( !$entry ) {
        $c->halt(404);
    }
    if ( $entry->{user} != $user->{id} || $c->req->param("__method") ne "DELETE" )
    {
        $c->halt(400);
    }
    $self->dbh->query("DELETE FROM entries WHERE id=?", $id);
    $c->render_json({
        ok => JSON::true,
    });
};


get '/image/:image' => [qw/ get_user /] => sub {
    my ( $self, $c ) = @_;
    my $user  = $c->stash->{user};
    my $image = $c->args->{image};
    my $size  = $c->req->param("size") || "l";
    my $dir   = $self->load_config->{data_dir};
    my $entry = $self->dbh->select_row(
        "SELECT * FROM entries WHERE image=?", $image,
    );
    if ( !$entry ) {
        $c->halt(404);
    }
    if ( $entry->{publish_level} == 0 ) {
        if ( $user && $entry->{user} == $user->{id} ) {
            # publish_level==0 はentryの所有者しか見えない
            # ok
        }
        else {
            $c->halt(404);
        }
    }
    elsif ( $entry->{publish_level} == 1 ) {
        # publish_level==1 はentryの所有者かfollowerしか見えない
        if ( $user && $entry->{user} == $user->{id} ) {
            # ok
        } else {
            my $follow = $self->dbh->select_row(
                "SELECT * FROM follow_map WHERE user=? AND target=?",
                $user->{id}, $entry->{user},
            );
            $c->halt(404) if !$follow;
        }
    }

    my $w = $size eq "s" ? IMAGE_S
          : $size eq "m" ? IMAGE_M
          : $size eq "l" ? IMAGE_L
          :                IMAGE_L;
    my $h = $w;
    my $data;
    if ($w) {
        my $file = $self->crop_square("$dir/image/${image}.jpg", "jpg");
        $data = $self->convert($file, "jpg", $w, $h);
        unlink $file;
    }
    else {
        open my $in, "<", "$dir/image/${image}.jpg" or $c->halt(500);
        $data = do { local $/; <$in> };
    }
    $c->res->content_type("image/jpeg");
    $c->res->content( $data );
    $c->res;
};

sub get_following {
    my ($self, $c) = @_;
    my $user = $c->stash->{user};
    my $following = $self->dbh->select_all(
        "SELECT users.* FROM follow_map JOIN users ON (follow_map.target=users.id) WHERE follow_map.user = ? ORDER BY follow_map.created_at DESC",
        $user->{id},
    );
    $c->res->header("Cache-Control" => "no-cache");
    $c->render_json({
        users => [
            map {
                my $u = $_;
                +{
                    id   => number $u->{id},
                    name => string $u->{name},
                    icon => string $c->req->uri_for("/icon/" . $u->{icon}),
                };
            } @$following
        ],
    });
};

get '/follow' => [qw/ get_user require_user /] => \&get_following;

post '/follow' => [qw/ get_user require_user /] => sub {
    my ($self, $c) = @_;
    my $user = $c->stash->{user};
    for my $target ( $c->req->param("target") ) {
        next if $target == $user->{id};
        $self->dbh->query(
            "INSERT IGNORE INTO follow_map (user, target, created_at) VALUES (?, ?, now())",
            $user->{id}, $target,
        );
    }
    get_following($self, $c);
};

post '/unfollow' => [qw/ get_user require_user /] => sub {
    my ($self, $c) = @_;
    my $user = $c->stash->{user};
    for my $target ( $c->req->param("target") ) {
        next if $target == $user->{id};
        $self->dbh->query(
            "DELETE FROM follow_map WHERE user=? AND target=?",
            $user->{id}, $target,
        );
    }
    get_following($self, $c);
};

get '/timeline' => [qw/ get_user require_user /] => sub {
    my ($self, $c) = @_;
    my $user = $c->stash->{user};
    my $latest_entry = $c->req->param("latest_entry");
    my ($sql, @params);
    if ($latest_entry) {
        $sql = 'SELECT * FROM (SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) AND id > ? ORDER BY id LIMIT 30) AS e ORDER BY e.id DESC';
        @params = ($user->{id}, $user->{id}, $latest_entry);
    }
    else {
        $sql = 'SELECT * FROM entries WHERE (user=? OR publish_level=2 OR (publish_level=1 AND user IN (SELECT target FROM follow_map WHERE user=?))) ORDER BY id DESC LIMIT 30';
        @params = ($user->{id}, $user->{id});
    }
    my $start = time;
    my @entries;
    while ( time - $start < $TIMEOUT ) {
        my $entries = $self->dbh->select_all($sql, @params);
        if (@$entries == 0) {
            sleep $INTERVAL;
            next;
        }
        else {
            @entries = @$entries;
            $latest_entry = $entries[0]->{id};
            last;
        }
    }
    $c->res->header("Cache-Control" => "no-cache");
    $c->render_json({
        latest_entry => number $latest_entry,
        entries => [
            map {
                my $entry = $_;
                my $user  = $self->dbh->select_row(
                    "SELECT * FROM users WHERE id=?", $entry->{user},
                );
                +{
                    id         => number $entry->{id},
                    image      => string $c->req->uri_for("/image/" . $entry->{image}),
                    publish_level => number $entry->{publish_level},
                    user => {
                        id   => number $user->{id},
                        name => string $user->{name},
                        icon => string $c->req->uri_for("/icon/" . $user->{icon}),
                    },
                }
            } @entries
        ]
    });
};


1;
