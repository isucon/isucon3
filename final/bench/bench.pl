#!/usr/bin/env perl
use strict;
use warnings;
use 5.12.0;
use lib "lib";
use Isucon2013Final::Bench;
use Parallel::Benchmark;
use Getopt::Long;
use Data::Dumper;
use Path::Tiny;
use Time::HiRes qw/ time /;

my $time     = 60;
my $workload = 1;
my $dir;
my $method;
my $host;
GetOptions(
    "time=i"     => \$time,
    "workload=i" => \$workload,
    "dir=s"      => \$dir,
    "method=s"   => \$method,
    "host=s"     => \$host,
);
Isucon2013Final::Bench->source_dir($dir);

my $endpoint  = URI->new(shift) || die "no endpoint";
my $processes = 6;
my $dispatch  = {
    0 => "post",
    1 => "view",
    2 => "check",
    3 => "crawl",
};
my $default = "timeline";
my $concurrency = $method ? 1
                          : $workload * $processes;
my $bench = Parallel::Benchmark->new(
    time        => $time,
    concurrency => $concurrency,
    setup => sub {
        my ($self, $n) = @_;
        $self->stash->{bench} = Isucon2013Final::Bench->new(
            endpoint => $endpoint,
            timeout  => $time,
            host     => $host // $endpoint->host,
        );
    },
    teardown => sub {
        my ($self, $n) = @_;
        delete $self->stash->{bench};
    },
    benchmark => sub {
        my ($self, $n) = @_;
        my $type = $n % $processes;
        $self->stash->{bench}->run($method // $dispatch->{$type} // $default);
    }
);

{
    my $b = Isucon2013Final::Bench->new(
        endpoint => $endpoint,
        timeout  => $time,
        host     => $host // $endpoint->host,
    );
    $b->run("post_get_delete_get");
}

$bench->run();

