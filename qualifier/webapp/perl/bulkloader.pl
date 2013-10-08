#!/usr/bin/env perl
use strict;
use JSON;
use Path::Tiny;
use DBIx::Sunny;
use Digest::SHA qw/ sha256_hex /;
use Time::Piece;

my $config = decode_json( path($ARGV[0])->slurp );
my $scale  = $ARGV[1];

my $dbconf = $config->{database};
my $dbh    = DBIx::Sunny->connect(
    "dbi:mysql:database=${$dbconf}{dbname};host=${$dbconf}{host};port=${$dbconf}{port}", $dbconf->{username}, $dbconf->{password}, {
        RaiseError => 1,
        AutoCommit => 1,
    },
);
my @md = map { chomp; $_ } grep /\.md$/, qx{ locate .md };

$dbh->query("TRUNCATE users");
$dbh->query("TRUNCATE memos");
my $total = 0;
my $now = localtime;
$now = $now - 86400;
for my $n ( 1 .. $scale ) {
    my $username = "isucon$n";
    my $salt     = substr( sha256_hex( time() . $username ), 0, 8 );
    my $password_hash = sha256_hex( $salt, $username );
    my $txn = $dbh->txn_scope;
    $dbh->query(
        'INSERT INTO users (username, password, salt) VALUES (?, ?, ?)',
        $username, $password_hash, $salt,
    );
    my $user_id = $dbh->last_insert_id;
    for ( 1 .. rand(100) + 1 ) {
        $total ++;
        my $t = $now + $total;
        $dbh->query(
            'INSERT INTO memos (user, is_private, content, created_at) VALUES (?, ?, ?, ?)',
            $user_id,
            (rand > 0.5 ? 1 : 0),
            path($md[ int rand(scalar @md) ])->slurp,
            $t->strftime('%Y-%m-%d %H:%M:%S'),
        );
    }
    $txn->commit;
}

