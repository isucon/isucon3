#!/usr/bin/env perl
use 5.12.0;
use JSON;
use DBIx::Sunny;
use Path::Tiny;
use Digest::SHA qw/ sha256_hex /;
use List::Util qw/ shuffle /;
use File::Copy;
use String::Random qw/ random_regex /;
use Log::Minimal;

$ENV{ISUCON_ENV} ||= "local";
my $config = do {
    open my $fh, "<", "../config/$ENV{ISUCON_ENV}.json" or die $!;
    decode_json(do { local $/; <$fh> });
};
my $dbh = do {
    my $dbconf = $config->{database};
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

$dbh->do("TRUNCATE users");
$dbh->do("TRUNCATE entries");
$dbh->do("TRUNCATE follow_map");

my $source_dir = path(shift) || die "no source dir";
my $data_dir   = path($config->{data_dir});
my $scale = shift || 1;
my @icon  = grep { $_->basename =~ /\.png$/ } $source_dir->children;
my @image = grep { $_->basename =~ /\.jpg$/ } $source_dir->children;

my $users   = $scale * 100;
my $entries = $scale * 50;
my @user_id;
my @entry_id = shuffle( 1 .. $users * $entries * 3 );
my $image_serial = 0;
my $user_serial  = 0;

my $txn = $dbh->txn_scope;
for my $uid ( 1 .. $users ) {
    my $user_image_serial = 0;
    $user_serial++;
    my $icon = sha256_hex("icon_${user_serial}");
    $dbh->query(
        "INSERT INTO users (name, api_key, icon) VALUES(?, ?, ?)",
        random_regex("[a-z][a-z0-9]{2,15}"),
        sha256_hex("api_key_$uid"),
        $icon,
    );
    my $user_id = $dbh->last_insert_id;
    push @user_id, $user_id;
    copy( $icon[ int rand(scalar @icon) ], "$data_dir/icon/$icon.png" ) or warn $!
        unless -e "$data_dir/icon/$icon.png";

    for ( 1 .. int($entries + rand($entries * 2)) ) { # 最低 entries はエントリがある
        $user_image_serial++;
        $image_serial++;
        my $image = sha256_hex("image_${user_serial}_${user_image_serial}");
        my $publish_level = $user_image_serial % 3;
        $dbh->query(
            "INSERT INTO entries (id, user, image, publish_level, created_at) VALUES(?, ?, ?, ?, now())",
            pop(@entry_id), $user_id, $image, $publish_level,
        );
        copy( $image[ int rand(scalar @image) ], "$data_dir/image/$image.jpg" ) or warn $!
            unless -e "$data_dir/image/$image.jpg";
    }
}
for my $user_id (@user_id) {
    next if $user_id % 13 == 0; # だれもフォローしないユーザを作っておく
    my $follows = int(rand() ** 3 * $users);

    my @target = (shuffle @user_id)[ 0 .. $follows - 1 ];
    for my $target_id ( @target ) {
        next if $user_id == $target_id;
        $dbh->query(
            "INSERT INTO follow_map (user, target, created_at) VALUES (?, ?, now())",
            $user_id, $target_id,
        );
    }
}
$txn->commit;

infof "users: $user_serial";
infof "images: $image_serial";
