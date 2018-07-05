use utf8;
use strict;
use HTML::Entities;
use JSON;
use EOSN::Util qw(read_file write_file);
use Getopt::Long;

our $infile = undef;
our $outdir_base = undef;
our %icons;
$icons{skip} ='<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-ban"></i></span>'; 
$icons{info} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-info-circle"></i></span>';
$icons{ok} = '<span class="icon is-medium has-text-success"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{warn} = '<span class="icon is-medium has-text-warning"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{err} = '<span class="icon is-medium has-text-warning2"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{crit} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-stop"></i></span>';

# ---------------------------------------------------------------------------
# Subroutines

sub get_report_options {
	GetOptions('input=s' => \$infile, 'output=s' => \$outdir_base) || exit 1;

	die "$0: input filename not given" if (! $infile);
	die "$0: output filename prefix not given" if (! $outdir_base);

	return from_json(read_file($infile) || die "$0: no data read");
}

sub generate_report {
	my %options = @_;

	my $text = $options{text};
	my $html = $options{html};

	generate_report_txt (%options) if ($text);
	generate_report_thtml (%options) if ($html);
}

sub generate_report_txt {
	my %options = @_;

	my $data = $options{data};
	my $report = $options{report};
	my $title = $options{title};
	my $outfile = $options{outfile};
	my @out;

	push (@out, "# $title\n");
	push (@out, "# Last Update: $$data{meta}{generated_at}\n");
	push (@out, "# For details on how this is generated, see https://validate.eosnation.io/about/\n");
	push (@out, "\n");
	foreach my $section (@$report) {
		my $name = $$section{name};
		my $rows = $$section{rows};
		my $prefix = $$section{name_prefix} || '';
		my $divider = $$section{section_divider} || 1;

		if ($name) {
			push (@out, "$prefix==== $name ====\n");
			if ($divider > 1) {
				push (@out, "\n");
			}
		}

		foreach my $line (@$rows) {
			my ($sprintf, @data) = @$line;
			push (@out, sprintf ($sprintf, @data));
		}

		push (@out, "\n");
	}

	write_file ($outdir_base . "/$outfile.txt", @out);
}

sub generate_report_thtml {
	my %options = @_;

	my $data = $options{data};
	my $report = $options{report};
	my $title = $options{title};
	my $columns = $options{columns};
	my $icons = $options{icons};
	my $noescape = $options{noescape};
	my $outfile = $options{outfile};
	my $text = $options{text};
	my @out;

	if ($text) {
		push (@out, "<p><a href=\"/$outfile.txt\">text version</a></p>");
		push (@out, "<br>\n");
	}

	foreach my $section (@$report) {
		my $name = $$section{name};
		my $rows = $$section{rows};

		push (@out, "<div class=\"card\">\n");
		if ($name) {
			push (@out, "<header class=\"card-header\">\n");
			push (@out, "<p class=\"card-header-title\"> $name </p>\n");
			push (@out, "</header>\n");
		}
		push (@out, "<div class=\"card-content\">\n");
		push (@out, "<table class=\"table is-striped\">\n") if ($columns);

		foreach my $line (@$rows) {
			my ($sprintf, @data) = @$line;
			my $formatted = '';
			$formatted .= "<tr>" if ($columns);
			foreach my $i (1 .. scalar(@data)) {
				my $value = $data[$i-1];
				if ($icons && $i == $icons) {
					$value = sev_html($value);
				} elsif ($noescape && $i == $noescape) {
					# no nothing
				} else {
					$value = encode_entities ($value);
				}
				$formatted .= "<td>$value</td>" if ($columns);
			}
			$formatted .= "</tr>" if ($columns);
			push (@out, $formatted);
		}

		push (@out, "</table>\n") if ($columns);
		push (@out, "</div>\n");
		push (@out, "</div>\n");
		push (@out, "<br>\n");
	}

	pop (@out);  # remove trailing <br>

	write_report_thtml (%options, content => \@out);
}

sub write_report_thtml {
	my %options = @_;

	my $content = $options{content};
	my $title = $options{title};
	my $outfile = $options{outfile};
	my @out;

	push (@out, "title = EOS Block Producer bp.json Validator: $title\n");
	push (@out, "h1 = $title\n");
	push (@out, "\n");
	push (@out, @$content);

	write_file ($outdir_base . "/$outfile.thtml", @out);
}

sub sev_html {
	my ($value) = @_;

	return $icons{$value} || encode_entities ($value);
}

1;
