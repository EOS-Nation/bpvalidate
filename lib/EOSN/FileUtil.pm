package EOSN::FileUtil;

use utf8;
use strict;
use Exporter;
use File::Copy;
use Text::CSV;

use parent qw(Exporter);
our @EXPORT_OK = qw(write_file read_file read_csv read_csv_hash);

# --------------------------------------------------------------------------
# Subroutines

sub write_file {
	my ($filename, @content) = @_;

	my $fh;
	open ($fh, ">:utf8", "$filename.$$") || die "$0: cannot write to file=<$filename.$$>: $!\n";
	foreach my $entry (@content) {
		print $fh $entry;
	}
	close ($fh);
	move ("$filename.$$", $filename) || die "$0: cannot rename file=<$filename.$$> to file=<$filename>: $!\n";
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

sub read_csv {
	my ($filename) = @_;

	my @data;
	my $fh;
	open ($fh, "<:utf8", $filename) || die "$0: cannot open file=<$filename>: $!\n";
	my $csv = Text::CSV->new ({ binary => 1}) || die "$0: Text::CSV error: " . Text::CSV->error_diag;

	my @cols = @{$csv->getline ($fh)};
	$csv->column_names (@cols);
	while (my $row = $csv->getline_hr ($fh)) {
		push (@data, $row);
	}
	$csv->eof || die "$0: " . $csv->error_diag();

	return \@data;
}

sub read_csv_hash {
	my ($filename, $key) = @_;

	my %data;
	my $fh;
	open ($fh, "<:utf8", $filename) || die "$0: cannot open file=<$filename>: $!\n";
	my $csv = Text::CSV->new ({ binary => 1}) || die "$0: Text::CSV error: " . Text::CSV->error_diag;

	my @cols = @{$csv->getline ($fh)};
	$csv->column_names (@cols);
	while (my $row = $csv->getline_hr ($fh)) {
		my $x = $$row{$key};
		$data{$x} = $row;
	}
	$csv->eof || die "$0: " . $csv->error_diag();

	return \%data;
}

1;
