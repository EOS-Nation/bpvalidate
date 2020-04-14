use utf8;
use strict;
use HTML::Entities;
use JSON;
use EOSN::FileUtil qw(read_file write_file read_csv_hash);
use Carp qw(confess);
use Getopt::Long;
use Date::Parse;
use Date::Format;
use Data::Dumper;

our $chain = undef;
our $infile = undef;
our $outdir = undef;
our $confdir = undef;

our %icons;
$icons{none} = '<!-- none -->';
$icons{bonus_blacklist} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-mask"></i></span>';
$icons{bonus_bpjson} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-cog"></i></span>';
$icons{bonus_history} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
$icons{bonus_hyperion} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
$icons{bonus_wallet} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-wallet"></i></span>';
$icons{bonus_chains} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-link"></i></span>';
$icons{bonus_ipv6} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-cloud"></i></span>';
$icons{skip} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-ban"></i></span>';
$icons{info} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-info-circle"></i></span>';
$icons{ok} = '<span class="icon is-medium has-text-success"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{warn} = '<span class="icon is-medium has-text-warning"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{err} = '<span class="icon is-medium has-text-warning2"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{crit} = '<span class="icon is-medium has-text-danger"><i class="fas fa-lg fa-stop"></i></span>';
$icons{check} = '<span class="icon is-medium has-text-grey"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{bp_top21} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-battery-full"></i></span>';
$icons{bp_standby} = '<span class="icon is-medium has-text-grey"><i class="fas fa-lg fa-battery-half"></i></span>';
$icons{bp_other} = '<span class="icon is-medium has-text-grey"><i class="fas fa-lg fa-battery-empty"></i></span>';

$icons{none_bw} = '<!-- none -->';
$icons{bonus_blacklist_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-mask"></i></span>';
$icons{bonus_bpjson_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-cog"></i></span>';
$icons{bonus_history_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
$icons{bonus_hyperion_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
$icons{bonus_wallet_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-wallet"></i></span>';
$icons{bonus_chains_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-link"></i></span>';
$icons{bonus_ipv6_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-cloud"></i></span>';
$icons{skip_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-ban"></i></span>';
$icons{info_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-info-circle"></i></span>';
$icons{ok_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{warn_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{err_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-exclamation-triangle"></i></span>';
$icons{crit_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-stop"></i></span>';
$icons{check_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-check-square"></i></span>';
$icons{bp_top21_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-battery-full"></i></span>';
$icons{bp_standby_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-battery-half"></i></span>';
$icons{bp_other_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-battery-empty"></i></span>';

our $labels;
our $languages;
our $chains;
our $producers;

# --------------------------------------------------------------------------
# Getter Subroutines

sub content_types {
	return ('txt', 'json', 'html');
}

sub labels {
	return $labels;
}

sub languages {
	return keys %$languages;
}

sub chains {
	return sort {$$chains{$a}{sort_order} <=> $$chains{$b}{sort_order}} keys %$chains;
}

sub outdir {
	return $outdir;
}

sub confdir {
	return $confdir;
}

sub chain {
	return $chain;
}

sub chain_properties {
	my ($chain) = @_;

	return $$chains{$chain};
}

sub classes {
	my @classes_available = (qw (regproducer org api_endpoint p2p_endpoint bpjson history hyperion wallet chains blacklist ipv6));
	my @classes_configured = ();

	foreach my $class (@classes_available) {
		next if (! exists $$chains{$chain}{"class_$class"});
		next if (! $$chains{$chain}{"class_$class"});
		push (@classes_configured, $class);
	}

	return @classes_configured;
}

# --------------------------------------------------------------------------
# Subroutines

sub get_report_options {
	GetOptions('chain=s' => \$chain, 'input=s' => \$infile, 'output=s' => \$outdir, 'config=s' => \$confdir) || exit 1;

	confess "$0: chain not given" if (! $chain);
	confess "$0: input filename not given" if (! $infile);
	confess "$0: output dir not given" if (! $outdir);
	confess "$0: config dir not given" if (! $confdir);

	$languages = read_csv_hash ("$confdir/languages.csv", 'lang');
	$labels = read_csv_hash ("$confdir/labels.csv", 'key');
	$chains = read_csv_hash ("$confdir/chains.csv", 'name');
	return from_json(read_file($infile) || confess "$0: no data read");
}

sub get_report_options_website {
	GetOptions('chain=s' => \$chain, 'output=s' => \$outdir, 'config=s' => \$confdir) || exit 1;

	confess "$0: output dir not given" if (! $outdir);
	confess "$0: config dir not given" if (! $confdir);

	$languages = read_csv_hash ("$confdir/languages.csv", 'lang');
	$labels = read_csv_hash ("$confdir/labels.csv", 'key');
	$chains = read_csv_hash ("$confdir/chains.csv", 'name');
	return undef;
}

sub get_report_options_chain {
	GetOptions('chain=s' => \$chain, 'output=s' => \$outdir, 'config=s' => \$confdir) || exit 1;

	confess "$0: chain not given" if (! $chain);
	confess "$0: output dir not given" if (! $outdir);
	confess "$0: config dir not given" if (! $confdir);

	$languages = read_csv_hash ("$confdir/languages.csv", 'lang');
	$labels = read_csv_hash ("$confdir/labels.csv", 'key');
	$chains = read_csv_hash ("$confdir/chains.csv", 'name');
	return undef;
}

sub generate_report {
	my (%options) = @_;

	my $content_type = $options{content_type};
	delete $options{content_type};

	#print ">> generate report content_type=<$content_type> file=<$options{outfile}> lang=<$options{lang}>\n";

	if (! $producers) {
		my $data = $options{data};
		foreach my $entry (@{$$data{producers}}) {
			my $producer = $$entry{regproducer}{owner};
			$$producers{$producer} = $entry;
		}
	}

	if ($content_type eq 'txt') {
		generate_report_txt (%options);
	} elsif ($content_type eq 'json') {
		generate_report_json (%options);
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
	my $chain = $options{chain} || confess "missing chain";
	my $title = $options{title} || label("title_$outfile", $lang);
	my @out;

	push (@out, "# $title\n");
	push (@out, "# " . label('txt_chain', $lang) . ' ' . label('chain_' . $chain, $lang) . "\n");
	push (@out, "# " . label('txt_update', $lang) . ' ' . datetime($$data{meta}{generated_at}, $lang) . "\n");
	push (@out, "# " . label('txt_about', $lang) . "\n");
	push (@out, "\n");
	foreach my $section (@$report) {
		my $name = $$section{name};
		$name = label ('unknown', $lang) if (defined $name && $name eq 'zzunknown');
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
			my $sprintf = $$line{sprintf};
			my $data = $$line{data};
			my $producer = $$line{producer};
			my $value = '';
			if ($$data[0]) {
				$value = sprintf ("$sprintf\n", @$data);
			}
			if ($producer) {
				push (@out, sprintf ("%12s", $producer) . " " . $value);
			} else {
				push (@out, $value);
			}
		}

		push (@out, "\n");
	}

	report_write_file ("$outfile.txt.$lang", @out);
}

sub generate_report_json {
	my %options = @_;

	my $lang = $options{lang};
	my $data = $options{data};
	my $report = $options{report};
	my $outfile = $options{outfile};
	my $chain = $options{chain} || confess "missing chain";
	my $title = $options{title} || label("title_$outfile", $lang);
	my %out;

	$out{meta}{title}{value} = $title;
	$out{meta}{network}{label} = label('txt_chain', $lang);
	$out{meta}{network}{value} = label('chain_' . $chain, $lang);
	$out{meta}{update}{label} = label('txt_update', $lang);
	$out{meta}{update}{value} = datetime($$data{meta}{generated_at}, $lang);
	$out{meta}{details}{value} = label('txt_about', $lang);

	foreach my $section (@$report) {
		my $name = $$section{name};
		$name = label ('unknown', $lang) if (defined $name && $name eq 'zzunknown');
		my $rows = $$section{rows};
		my $prefix = $$section{name_prefix} || '';
		my $divider = $$section{section_divider} || 1;

		my @out;
		foreach my $line (@$rows) {
			my $sprintf = $$line{sprintf};
			my $data = $$line{data};
			my $producer = $$line{producer};
			if ($producer) {
				push (@out, [{
						name => $producer,
						html_name => encode_entities($$producers{$producer}{info}{name} || $producer),
						rank => $$producers{$producer}{info}{rank}
					},
					@$data
				]);
			} else {
				push (@out, [@$data]);
			}
		}
		if ($name) {
			$out{report}{$name} = \@out;
		} else {
			$out{report} = \@out;
		}
	}

	report_write_file ("$outfile.json.$lang", to_json (\%out, {canonical => 1}));
}

sub generate_report_thtml {
	my %options = @_;

	my $lang = $options{lang};
	my $data = $options{data};
	my $report = $options{report};
	my $columns = $options{columns};
	my $outfile = $options{outfile};
	my $text = $options{text};
	my $json = $options{json};
	my @out;

	if ($text) {
		push (@out, "<p><a href=\"../$outfile.txt\">" . label('label_text_version', $lang) . "</a></p>");
	}
	if ($json) {
		push (@out, "<p><a href=\"../$outfile.json\">" . label('label_json_version', $lang) . "</a></p>");
	}
	if ($text || $json) {
		push (@out, "<br>\n");
	}

	foreach my $section (@$report) {
		my $name = $$section{title} || $$section{name};
		$name = label ('unknown', $lang) if (defined $name && $name eq 'zzunknown');
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
			my $sprintf = $$line{sprintf};
			my $data = $$line{data};
			my $producer = $$line{producer};
			my $icons = $$line{icons};
			my $class = $$line{class};
			my $href = $$line{href};
			my $noescape = $$line{noescape};
			my $formatted = '';
			if ($columns) {
				$formatted .= "<tr>";
				if ($producer) {
					my $producer_name_html = encode_entities($$producers{$producer}{info}{name} || $producer);
					$formatted .= "<td>$$producers{$producer}{info}{rank}</td>";
					$formatted .= "<td>" . bp_logo ($$producers{$producer}) . "</td>";
					$formatted .= "<td><a href=\"../producers/$producer.html\">$producer_name_html</a></td>";
				}
				foreach my $i (1 .. scalar(@$data)) {
					my $value = $$data[$i-1];
					if ($icons && $i == $icons) {
						my $classx = $$data[$class - 1];
						$value = sev_html(kind => $value, class => $classx, lang => $lang);
					} elsif ($class && $i == $class) {
						$value = label("class_$value", $lang);
					} elsif ($href && $i == $href) {
						$value = "<a href=\"$value\">$value</a>";
					} elsif ($noescape && $i == $noescape) {
						# no nothing
					} else {
						$value = encode_entities ($value);
					}
					if (defined $value) {
						$formatted .= "<td>$value</td>";
					}
				}
				$formatted .= "</tr>";
			} else {
				$formatted = sprintf("$sprintf<br>\n", @$data);
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
	my $chain = $options{chain} || confess "missing chain";
	my $title = $options{title} || label("title_$outfile", $lang);
	my @out;

	push (@out, "chain = $chain\n");
	push (@out, "title = %title_site%: $title\n");
	push (@out, "h1 = $title\n");
	push (@out, "\n");
	push (@out, @$content);

	report_write_file ("$outfile.thtml.$lang", @out);
}

sub sev_html {
	my (%options) = @_;

	my $kind = $options{kind};
	my $class = $options{class};
	my $lang = $options{lang};
	my $color = $options{color};

	my $html = $icons{$kind} || encode_entities ($kind);
	if ($color) {
		$html = $icons{"${kind}_${color}"} || encode_entities ($kind);
	}

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

	my $service = $$options{service};
	my $feature = $$options{feature};
	my $count = $$options{count};
	my $value = $$options{value};
	my $value_time = $$options{value_time};
	my $suggested_value = $$options{suggested_value};
	my $request_timeout = $$options{request_timeout};
	my $cache_timeout = $$options{cache_timeout};
	my $elapsed_time = $$options{elapsed_time};
	my $check_time = $$options{check_time};
	my $kind = $$options{kind} || confess "missing kind";
	my $detail = $$options{detail} || confess "missing detail";
	my $threshold = $$options{threshold};
	my $field = $$options{field};
	my $contract = $$options{contract};
	my $node_type = $$options{node_type};
	my $resource = $$options{resource};
	my $api_url = $$options{api_url};
	my $url = $$options{url};
	my $post_data = $$options{post_data};
	my $response_url = $$options{response_url};
	my $response_host = $$options{response_host};
	my $host = $$options{host};
	my $ip = $$options{ip};
	my $dns = $$options{dns};
	my $port = $$options{port};
	my $explanation = $$options{explanation};
	my $see1 = $$options{see1};
	my $see2 = $$options{see2};
	my $last_update_time = $$options{last_update_time};
	my $diff = $$options{diff};

	# ---------- formatting

	if ($url && $url !~ m#^https?://.#) {
		$host = $url;
		$url = undef;
	}
	if ($url && $response_url) {
		$response_url = undef if ($url eq $response_url);
	}

	$request_timeout .= ' ' . label('time_s', $lang) if ($request_timeout);

	if ($cache_timeout) {
		$cache_timeout = undef if ($cache_timeout < 1800);
	}
	if ($cache_timeout) {
		if ($cache_timeout > 3600) {
			$cache_timeout = int ($cache_timeout / 3600);
			$cache_timeout .= ' ' . label('time_h', $lang);
		} else {
			$cache_timeout = int ($cache_timeout / 60);
			$cache_timeout .= ' ' . label('time_m', $lang);
		}
	}

	$elapsed_time .= ' s' if ($elapsed_time);

	# ---------- output

	$detail .= format_message_entry ('msg_service', $service, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_feature', $feature, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_threshold', $threshold, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_count', $count, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_value', $value, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_value_time', datetime($value_time, $lang), 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_suggested_to_use_value', $suggested_value, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_field', $field, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_contract', $contract, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_having_node_type', $node_type, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_resource', $resource, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_api_url', $api_url, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_url', $url, 1, $content_type, $lang);
	$detail .= format_message_entry ('msg_post_data', $post_data, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_redirected_to_response_url', $response_url, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_response_from_host', $response_host, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_host', $host, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_ip', $ip, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_dns', $dns, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_port', $port, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_elapsed_time', $elapsed_time, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_timeout', $request_timeout, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_validated_at', datetime($check_time, $lang), 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_validated_every', $cache_timeout, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_explanation', $explanation, 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_see', $see1, 1, $content_type, $lang);
	$detail .= format_message_entry ('msg_see', $see2, 1, $content_type, $lang);
	$detail .= format_message_entry ('msg_last_updated_at', datetime($last_update_time, $lang), 0, $content_type, $lang);
	$detail .= format_message_entry ('msg_diff', $diff, 2, $content_type, $lang);

	return $detail;
}

sub format_message_entry {
	my ($key, $value, $is_url, $content_type, $lang) = @_;

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
		return ', ' . label($key, $lang) . '=&lt;' . $value . '&gt;';
	} else {
		if ($is_url == 2) {
			return "";
		} else {
			return ', ' . label($key, $lang) . '=<' . $value .'>';
		}
	}
}

sub report_write_file {
	my ($filename, @out) = @_;

	my $report_dir = $outdir . "/$chain";
	write_file ($report_dir . "/" . $filename, @out);
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
	my $is_standby = $$entry{info}{is_standby};
	my $is_top_21 = $$entry{info}{is_top_21};

	my $selected = 0;
	if ($is_top_21) {
		$selected = 1;
	} elsif ($is_standby) {
		$selected = 1;
	}

	return $selected;
}

sub bp_logo {
	my ($entry) = @_;

	my $logo = $$entry{output}{resources}{social_logo_256}[0]{address} || '';
	$logo = '' if ($logo !~ m#https://#);

	if ($logo) {
		$logo = "<figure class=\"image is-24x24\"><img src=\"$logo\"></figure>\n";
	} else {
		$logo = "<figure class=\"image is-24x24\"></figure>\n";
	}

	return $logo;
}

sub whois_org {
	my ($node) = @_;

	my %orgs;

	foreach my $host (@{$$node{hosts}}) {
		my $org = $$host{organization};
		next if (! $org);
		$orgs{$org} = 1;
	}

	return join ('; ', sort keys %orgs);
}

1;
