#!/usr/bin/perl -w

use Number::Format;

my $nf = new Number::Format;
print $nf->format_bytes('129002', precision => 2, mode => 'iec'), "\n";
print $nf->format_number(-30129121.2312312, 2, 1), "\n";
