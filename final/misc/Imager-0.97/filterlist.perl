#!/usr/bin/perl 
use strict;
use Imager;
print "Filter          Arguments\n";
for my $filt (keys %Imager::filters) {
    my @callseq=@{$Imager::filters{$filt}{'callseq'} || {}};
    my %defaults=%{$Imager::filters{$filt}{'defaults'} || {}};
    shift(@callseq);
    my @b=map { exists($defaults{$_}) ? $_.'('.$defaults{$_}.')' : $_ } @callseq;
    my $str=join(" ",@b);    
    printf("%-15s %s\n",$filt,$str );
}
