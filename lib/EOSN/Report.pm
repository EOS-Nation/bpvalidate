use utf8;
use strict;
use HTML::Entities;
use JSON;
use EOSN::FileUtil qw(read_file write_file read_csv_hash);
use Carp qw(confess);
use Getopt::Long;
use Date::Parse;
use Date::Format;

our $infile = undef;
our $outdir = undef;
our $confdir = undef;
our %icons;
$icons{skip} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-ban"></i></span>';
$icons{info} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-info-circle"></i></span>';
$icons{ok} = '<span class="icon is-medium has-text-success"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{warn} = '<span class="icon is-medium has-text-warning"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{err} = '<span class="icon is-medium has-text-warning2"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{crit} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-stop"></i></span>';
$icons{bp_top21} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-certificate"></i></span>';
$icons{bp_standby} = '<span class="icon is-medium has-text-grey"><i class="fas fa-lg fa-certificate"></i></span>';

our $labels;
our $languages;

# --------------------------------------------------------------------------
# Getter Subroutines

sub content_types {
	return ('txt', 'html');
}

sub languages {
	return keys %$languages;
}

sub labels {
	return $labels;
}

sub outdir {
	return $outdir;
}

# --------------------------------------------------------------------------
# Subroutines

sub get_report_options {
	GetOptions('input=s' => \$infile, 'output=s' => \$outdir, 'config=s' => \$confdir) || exit 1;

	confess "$0: input filename not given" if (! $infile);
	confess "$0: output dir not given" if (! $outdir);
	confess "$0: config dir not given" if (! $confdir);

	$languages = read_csv_hash ("$confdir/languages.csv", 'lang');
	$labels = read_csv_hash ("$confdir/labels.csv", 'key');
	return from_json(read_file($infile) || confess "$0: no data read");
}

sub generate_report {
	my (%options) = @_;

	my $content_type = $options{content_type};
	delete $options{content_type};

	#print ">> generate report content_type=<$content_type> file=<$options{outfile}> lang=<$options{lang}>\n";

	if ($content_type eq 'txt') {
		generate_report_txt (%options);
	} elsif ($content_type eq 'html') {
		generate_report_thtml (%options);
	} else {
		die "$0: unknown content_type";
	}
}

sub generate_report_txt {
	my %options = @_;

	my $lang = $options{lang};
	my $data = $options{data};
	my $report = $options{report};
	my $outfile = $options{outfile};
	my $title = $options{title} || label("title_$outfile", $lang);
	my @out;

	push (@out, "# $title\n");
	push (@out, "# " . label('txt_update', $lang) . ": " . datetime($$data{meta}{generated_at}, $lang) . "\n");
	push (@out, "# " . label('txt_about', $lang) . "\n");
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

	report_write_file ("$outfile.txt.$lang", @out);
}

sub generate_report_thtml {
	my %options = @_;

	my $lang = $options{lang};
	my $data = $options{data};
	my $report = $options{report};
	my $columns = $options{columns};
	my $icons = $options{icons};
	my $class = $options{class};
	my $noescape = $options{noescape};
	my $outfile = $options{outfile};
	my $text = $options{text};
	my @out;

	if ($text) {
		push (@out, "<p><a href=\"/$outfile.txt\">" . label('label_text_version', $lang) . "</a></p>");
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
						$value = sev_html($value, $classx, $lang);
					} elsif ($class && $i == $class) {
						$value = label("class_$value", $lang);
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

	my $lang = $options{lang};
	my $content = $options{content};
	my $outfile = $options{outfile};
	my $title = $options{title} || label("title_$outfile", $lang);
	my @out;

	push (@out, "title = EOS Block Producer bp.json Validator: $title\n");
	push (@out, "h1 = $title\n");
	push (@out, "\n");
	push (@out, @$content);

	report_write_file ("$outfile.thtml.$lang", @out);
}

sub sev_html {
	my ($kind, $class, $lang) = @_;

	my $html = $icons{$kind} || encode_entities ($kind);

	if ($class) {
		my $title_class = label("class_$class", $lang);
		my $title = label("check_$kind", $lang);
		$html =~ s/ / title="$title_class: $title" /;
	} else {
		my $title = label("$kind", $lang);
		$html =~ s/ / title="$title" /;
	}
	
	return $html;
}

sub flag_html {
	my ($alpha2) = @_;

	return "<span class=\"flag-icon flag-icon-$alpha2\"></span>";
}

sub generate_message {
	my ($options, %params) = @_;

	my $content_type = $params{content_type} || die;
	my $lang = $params{lang} || die;

	my $count = $$options{count};
	my $value = $$options{value};
	my $suggested_value = $$options{suggested_value};
	my $target = $$options{target};
	my $kind = $$options{kind} || confess "missing kind";
	my $detail = $$options{detail} || confess "missing detail";
	my $field = $$options{field};
	my $contract = $$options{contract};
	my $node_type = $$options{node_type};
	my $resource = $$options{resource};
	my $api_url = $$options{api_url};
	my $url = $$options{url};
	my $response_url = $$options{response_url};
	my $host = $$options{host};
	my $ip = $$options{ip};
	my $dns = $$options{dns};
	my $port = $$options{port};
	my $explanation = $$options{explanation};
	my $see1 = $$options{see1};
	my $see2 = $$options{see2};
	my $last_update_time = $$options{last_update_time};
	my $diff = $$options{diff};

	if ($url && $url !~ m#^https?://.#) {
		$host = $url;
		$url = undef;
	}
	if ($url && $response_url) {
		$response_url = undef if ($url eq $response_url);
	}

	$detail .= format_message_entry ('count', $count, 0, $content_type);
	$detail .= format_message_entry ('value', $value, 0, $content_type);
	$detail .= format_message_entry ('suggested to use value', $suggested_value, 0, $content_type);
	$detail .= format_message_entry ('target', $target, 0, $content_type);
	$detail .= format_message_entry ('field', $field, 0, $content_type);
	$detail .= format_message_entry ('contract', $contract, 0, $content_type);
	$detail .= format_message_entry ('having node_type', $node_type, 0, $content_type);
	$detail .= format_message_entry ('resource', $resource, 0, $content_type);
	$detail .= format_message_entry ('api_url', $api_url, 0, $content_type);
	$detail .= format_message_entry ('url', $url, 1, $content_type);
	$detail .= format_message_entry ('redirected to response_url', $response_url, 0, $content_type);
	$detail .= format_message_entry ('host', $host, 0, $content_type);
	$detail .= format_message_entry ('ip', $ip, 0, $content_type);
	$detail .= format_message_entry ('dns', $dns, 0, $content_type);
	$detail .= format_message_entry ('port', $port, 0, $content_type);
	$detail .= format_message_entry ('explanation', $explanation, 0, $content_type);
	$detail .= format_message_entry ('see', $see1, 1, $content_type);
	$detail .= format_message_entry ('see', $see2, 1, $content_type);
	$detail .= format_message_entry ('last updated at', datetime($last_update_time, $lang), 0, $content_type);
	$detail .= format_message_entry ('diff', $diff, 2, $content_type);

	return $detail;
}

sub format_message_entry {
	my ($key, $value, $is_url, $content_type) = @_;

	return '' if (! defined $value);
	return '' if ($value eq '');

	if ($content_type eq 'html') {
		if ($is_url == 1) {
			$value = '<a href="' . $value . '">' . $value . '</a>';
		} elsif ($is_url == 2) {
			$value = '<xmp>' . $value . '</xmp>';
		} else {
			$value = encode_entities ($value);
		}
		return ", $key=&lt;$value&gt;";
	} else {
		if ($is_url == 2) {
			return "";
		} else {
			return ", $key=<$value>";
		}
	}
}

sub report_write_file {
	my ($filename, @out) = @_;

	write_file ($outdir . "/" . $filename, @out);
}

sub label {
	my ($key, $lang) = @_;

	#return "[" . ($$labels{$key}{"label_$lang"} || $$labels{$key}{label_en} || $key) . "]";
	return $$labels{$key}{"label_$lang"} || $$labels{$key}{label_en} || $key;
}

sub datetime {
	my ($value, $lang) = @_;

	return '' if (! defined $value);

	my $unixtime = str2time($value);
	return time2str(label('format_datetime', $lang), $unixtime, 'UTC');
}

sub is_important_bp {
	my ($entry) = @_;

	my $rank = $$entry{info}{rank};
	my $votep = $$entry{info}{vote_percent};

	my $selected = 0;
	if ($rank <= 21) {
		$selected = 1;
	} elsif ($votep > 0.5) {
		$selected = 1;
	}

	return $selected;
}

1;
