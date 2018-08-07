#!/usr/bin/perl -w

# apt install libjson-perl
# Usage: bpjson2chain.pl producername < bp.json

use strict;
use JSON;

my $producer = $ARGV[0] || "insertproducername";
my $data = "";

while (<>) {
	$data .= $_;
}

my $json = from_json($data) || die "$0: cannot parse JSON data";
my $args = {owner => $producer, json => to_json($json)};
print "cleos.sh push action producerjson set '" . to_json($args) . "' -p $producer\@active\n";
