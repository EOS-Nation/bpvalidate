use utf8;
use strict;
use HTML::Entities;
use JSON;
use EOSN::FileUtil qw(read_file write_file);
use Carp qw(confess);
use Getopt::Long;

our $infile = undef;
our $outdir_base = undef;
our %icons;
$icons{skip} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-ban"></i></span>';
$icons{info} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-info-circle"></i></span>';
$icons{ok} = '<span class="icon is-medium has-text-success"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{warn} = '<span class="icon is-medium has-text-warning"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{err} = '<span class="icon is-medium has-text-warning2"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{crit} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-stop"></i></span>';
$icons{selected} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-certificate"></i></span>';
$icons{standby} = '<span class="icon is-medium has-text-grey"><i class="fas fa-lg fa-certificate"></i></span>';

our %labels;
$labels{general} = 'General Info';
$labels{regproducer} = 'Regproducer';
$labels{org} = 'Organization';
$labels{endpoint} = 'Endpoints';
$labels{ipv6} = 'IPv6';
$labels{skip} = 'Skipped';
$labels{info} = 'Information';
$labels{ok} = 'OK';
$labels{warn} = 'Warning';
$labels{err} = 'Error';
$labels{crit} = 'Critical Error';
$labels{selected} = 'Selected Block Producer';
$labels{selected} = 'Paid Standby Block Producer';

# --------------------------------------------------------------------------
# Subroutines

sub get_report_options {
	GetOptions('input=s' => \$infile, 'output=s' => \$outdir_base) || exit 1;

	confess "$0: input filename not given" if (! $infile);
	confess "$0: output filename prefix not given" if (! $outdir_base);

	return from_json(read_file($infile) || confess "$0: no data read");
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
	my $class = $options{class};
	my $noescape = $options{noescape};
	my $outfile = $options{outfile};
	my $text = $options{text};
	my @out;

	if ($text) {
		push (@out, "<p><a href=\"/$outfile.txt\">text version</a></p>");
		push (@out, "<br>\n");
	}

	foreach my $section (@$report) {
		my $name = $$section{title} || $$section{name};
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
			if ($columns) {
				$formatted .= "<tr>";
				foreach my $i (1 .. scalar(@data)) {
					my $value = $data[$i-1];
					if ($icons && $i == $icons) {
						my $classx = $data[$class - 1];
						$value = sev_html($value, $classx);
					} elsif ($class && $i == $class) {
						$value = $labels{$value} || $value;
					} elsif ($noescape && $i == $noescape) {
						# no nothing
					} else {
						$value = encode_entities ($value);
					}
					$formatted .= "<td>$value</td>"
				}
				$formatted .= "</tr>";
			} else {
				$formatted = sprintf("$sprintf<br>", @data);
			}

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
	my ($kind, $class) = @_;

	my $html = $icons{$kind} || encode_entities ($kind);
	my $labels = $labels{$kind} || $kind;

	if ($class) {
		my $labelc = $labels{$class} || $class;
		$html =~ s/ / title="$labelc: $labels" /;
	} else {
		$html =~ s/ / title="$labels" /;
	}
	
	return $html;
}

sub flag_html {
	my ($alpha2) = @_;

	return "<span class=\"flag-icon flag-icon-$alpha2\"></span>";
}

sub generate_message {
	my ($options) = @_;

	my $value = $$options{value};
	my $suggested_value = $$options{suggested_value};
	my $target = $$options{target};
	my $kind = $$options{kind} || confess "missing kind";
	my $detail = $$options{detail} || confess "missing detail";
	my $field = $$options{field};
	my $resource = $$options{resource};
	my $url = $$options{url};
	my $response_url = $$options{response_url};
	my $host = $$options{host};
	my $ip = $$options{ip};
	my $dns = $$options{dns};
	my $port = $$options{port};
	my $explanation = $$options{explanation};

	if ($url && $url !~ m#^https?://.#) {
		$host = $url;
		$url = undef;
	}
	if ($url && $response_url) {
		$response_url = undef if ($url eq $response_url);
	}

	$detail .= " value=<$value>" if ($value);
	$detail .= " suggested to use value=<$suggested_value>" if ($suggested_value);
	$detail .= " target=<$target>" if ($target);
	$detail .= " for field=<$field>" if ($field);
	$detail .= " for resource=<$resource>" if ($resource);
	$detail .= " for url=<$url>" if ($url);
	$detail .= " redirected to response_url=<$response_url>" if ($response_url);
	$detail .= " for host=<$host>" if ($host);
	$detail .= " for ip=<$ip>" if ($ip);
	$detail .= " for dns=<$dns>" if ($dns);
	$detail .= " for port=<$port>" if ($port);
	$detail .= "; see $explanation" if ($explanation);

	return $detail;
}

1;
