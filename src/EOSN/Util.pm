package EOSN::Util;

use utf8;
use strict;
use Exporter;

use parent qw(Exporter);
our @EXPORT_OK = qw(hostname write_file read_file);

# ---------------------------------------------------------------------------
# Subroutines

sub hostname {
	my $hostname = `hostname`;
	chomp ($hostname);
	$hostname .= '.eosn.io';
	return ($hostname);
}

sub write_file {
	my ($filename, $content) = @_;

	my $fh;
	open ($fh, ">:utf8", $filename) || die "$0: cannot write to file=<$filename>: $!\n";
	print $fh $content;
	close ($fh);
}

sub read_file {
	my ($filename) = @_;

	my $fh;
	open ($fh, "<:utf8", $filename) || die "$0: cannot read from file=<$filename>: $!\n";
	my @content;
	while (<$fh>) {
		chomp;
		push (@content, $_);
	}
	close ($fh);

	if (wantarray) {
		return @content;
	} else {
		return join ("\n", @content);
	}
}

1;
