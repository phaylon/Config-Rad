#!/usr/bin/env perl
use strictures 1;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Config::Rad;
use Data::Dump qw( pp );

my $rad = Config::Rad->new;
pp($rad->parse_string($ARGV[0] || ''));
