package EOSN::Validate::Report;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use warnings;
use HTML::Entities;
use JSON qw(to_json from_json);
use File::Slurp qw(read_file);
use EOSN::File qw(write_file_atomic);
use YAML qw(LoadFile);
use Carp qw(confess);
use Getopt::Long;
use Date::Parse;
use Date::Format;
use EOSN::Validate::Config;

# --------------------------------------------------------------------------
# Class Methods

sub new {
	my ($class) = shift;

	my ($self) = {};
	bless $self, $class;
	return $self->initialize (@_);
}

sub DESTROY {
	my ($self) = @_;

	$self->{config} = undef;
	$self->{chain} = undef;
	$self->{infile} = undef;
	$self->{producers} = undef;
}

# --------------------------------------------------------------------------
# Private Methods

sub initialize {
        my ($self) = @_;

	$self->{config} = EOSN::Validate::Config->new;
	$self->{chain} = undef;
	$self->{infile} = undef;
	$self->{producers} = undef;

        return $self;
}

# --------------------------------------------------------------------------
# Getter Methods

sub config {
	my ($self) = @_;

	return $self->{config};
}

sub chain {
	my ($self) = @_;

	return $self->{chain};
}

sub data {
	my ($self) = @_;

	return $self->{data};
}

sub producers {
	my ($self) = @_;

	return $self->{producers};
}

sub classes {
	my ($self) = @_;

	my $config = $self->config;
	my $chain = $self->chain;

	my @classes_available = (qw (regproducer org blocks api_endpoint p2p_endpoint bpjson history hyperion dfuse firehose atomic account chains ipv6));
	my @classes_configured = ();

	foreach my $class (@classes_available) {
		my $properties = $config->chain_properties ($chain);

		next if (! exists $$properties{"class_$class"});
		next if (! $$properties{"class_$class"});
		push (@classes_configured, $class);
	}

	return @classes_configured;
}

# --------------------------------------------------------------------------
# Public Methods

sub icons {
	my ($self) = @_;

	my %icons;

	$icons{none} = '<!-- none -->';
	$icons{class_regproducer} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-file-alt"></i></span>';
	$icons{class_org} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-sitemap"></i></span>';
	$icons{class_blocks} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-dice-d6"></i></span>';
	$icons{class_api_endpoint} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-server"></i></span>';
	$icons{class_p2p_endpoint} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-network-wired"></i></span>';
	$icons{class_bpjson} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-cog"></i></span>';
	$icons{class_history} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_hyperion} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_dfuse} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_firehose} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_atomic} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-atom"></i></span>';
	$icons{class_account} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-wallet"></i></span>';
	$icons{class_chains} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-link"></i></span>';
	$icons{class_ipv6} = '<span class="icon is-medium has-text-info"><i class="fas fa-lg fa-cloud"></i></span>';
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
	$icons{class_regproducer_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-file-alt"></i></span>';
	$icons{class_org_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-sitemap"></i></span>';
	$icons{class_blocks_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-dice-d6"></i></span>';
	$icons{class_api_endpoint_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-server"></i></span>';
	$icons{class_p2p_endpoint_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-network-wired"></i></span>';
	$icons{class_bpjson_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-cog"></i></span>';
	$icons{class_history_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_hyperion_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_dfuse_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_firehose_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-database"></i></span>';
	$icons{class_atomic_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-atom"></i></span>';
	$icons{class_account_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-wallet"></i></span>';
	$icons{class_chains_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-link"></i></span>';
	$icons{class_ipv6_bw} = '<span class="icon is-medium"><i class="fas fa-lg fa-cloud"></i></span>';
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

	return \%icons;
}

sub get_report_options {
	my ($self) = @_;

	my $chain;
	my $infile;

	GetOptions('chain=s' => \$chain, 'input=s' => \$infile) || exit 1;

	confess "$0: chain not given" if (! $chain);
	confess "$0: input filename not given" if (! $infile);

	$self->{chain} = $chain;
	$self->{infile} = $infile;

	my $data = from_json (read_file ($infile, {binmode => ':utf8'}));
	my $producers;

	foreach my $entry (@{$$data{producers}}) {
		my $producer = $$entry{regproducer}{owner};
		$$producers{$producer} = $entry;
	}

	$self->{producers} = $producers;
	$self->{data} = $data;

	return undef;
}

sub generate_report {
	my ($self, %options) = @_;

	my $content_type = $options{content_type};
	delete $options{content_type};

	#print ">> generate report content_type=<$content_type> file=<$options{outfile}> lang=<$options{lang}>\n";

	if ($content_type eq 'txt') {
		$self->generate_report_txt (%options);
	} elsif ($content_type eq 'json') {
		$self->generate_report_json (%options);
	} elsif ($content_type eq 'html') {
		$self->generate_report_thtml (%options);
	} else {
		die "$0: unknown content_type";
	}
}

sub generate_report_txt {
	my ($self, %options) = @_;

	my $data = $self->data;
	my $config = $self->config;
	my $webdir = $config->webdir;
	my $chain = $self->chain;
	my $lang = $options{lang};
	my $report = $options{report};
	my $outfile = $options{outfile};
	my $title = $options{title} || $config->label (key => "title_$outfile", lang => $lang);
	my @out;

	push (@out, "# $title\n");
	push (@out, "# " . $config->label (key => 'txt_chain', lang => $lang) . ' ' . $config->label (key => 'chain_' . $chain, lang => $lang) . "\n");
	push (@out, "# " . $config->label (key => 'txt_update', lang => $lang) . ' ' . $config->datetime (timestring => $$data{meta}{generated_at}, lang => $lang) . "\n");
	push (@out, "# " . $config->label (key => 'txt_about', lang => $lang) . "\n");
	push (@out, "\n");

	foreach my $section (@$report) {
		my $name = $$section{name};
		$name = $config->label (key => 'unknown', lang => $lang) if (defined $name && $name eq 'zzunknown');
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

	write_file_atomic ($webdir . '/' . $chain . '/' . "$outfile.txt.$lang", {binmode => ':utf8'}, @out);
}

sub generate_report_json {
	my ($self, %options) = @_;

	my $data = $self->data;
	my $producers = $self->producers;
	my $config = $self->config;
	my $webdir = $config->webdir;
	my $chain = $self->chain;
	my $lang = $options{lang};
	my $report = $options{report};
	my $outfile = $options{outfile};
	my $title = $options{title} || $config->label (key => "title_$outfile", lang => $lang);
	my %out;

	$out{meta}{title}{value} = $title;
	$out{meta}{network}{label} = $config->label (key => 'txt_chain', lang => $lang);
	$out{meta}{network}{value} = $config->label (key => 'chain_' . $chain, lang => $lang);
	$out{meta}{update}{label} = $config->label (key => 'txt_update', lang => $lang);
	$out{meta}{update}{value} = $config->datetime (timestring => $$data{meta}{generated_at}, lang => $lang);
	$out{meta}{details}{value} = $config->label (key => 'txt_about', lang => $lang);

	foreach my $section (@$report) {
		my $name = $$section{name};
		$name = $config->label (key => 'unknown', lang => $lang) if (defined $name && $name eq 'zzunknown');
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

	write_file_atomic ($webdir . '/' . $chain . '/' . "$outfile.json.$lang", {binmode => ':utf8'}, to_json (\%out, {canonical => 1}));
}

sub generate_report_thtml {
	my ($self, %options) = @_;

	my $data = $self->data;
	my $producers = $self->producers;
	my $config = $self->config;
	my $chain = $self->chain;
	my $lang = $options{lang};
	my $report = $options{report};
	my $columns = $options{columns};
	my $outfile = $options{outfile};
	my $text = $options{text};
	my $json = $options{json};
	my @out;

	if ($text) {
		push (@out, "<p><a href=\"../$outfile.txt\">" . $config->label (key => 'label_text_version', lang => $lang) . "</a></p>");
	}
	if ($json) {
		push (@out, "<p><a href=\"../$outfile.json\">" . $config->label (key => 'label_json_version', lang => $lang) . "</a></p>");
	}
	if ($text || $json) {
		push (@out, "<br>\n");
	}

	foreach my $section (@$report) {
		my $name = $$section{title} || $$section{name};
		$name = $config->label (key => 'unknown', lang => $lang) if (defined $name && $name eq 'zzunknown');
		my $rows = $$section{rows};

		if ($$section{name}) {
			push (@out, "<a name=\"$$section{name}\"></a>\n");
		}
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
			my $html_data = $$line{html_data};
			my $producer = $$line{producer};
			my $formatted = '';
			if ($columns) {
				$formatted .= "<tr>";
				if ($producer) {
					my $producer_name_html = encode_entities($$producers{$producer}{info}{name} || $producer);
					$formatted .= "<td>$$producers{$producer}{info}{rank}</td>";
					$formatted .= "<td>" . $self->bp_logo ($$producers{$producer}) . "</td>";
					$formatted .= "<td><a href=\"../producers/$producer.html\">$producer_name_html</a></td>";
				}
				foreach my $i (1 .. scalar (@$data)) {
					my $value = $$data[$i-1];
					if (defined $$html_data[$i-1]) {
						$value = $$html_data[$i-1];
					} else {
						$value = encode_entities ($value);
					}
					if (defined $value) {
						$formatted .= "<td>$value</td>";
					}
				}
				$formatted .= "</tr>";
			} else {
				$formatted = sprintf ("$sprintf<br>\n", @$data);
			}

			push (@out, $formatted);
		}

		push (@out, "</table>\n") if ($columns);
		push (@out, "</div>\n");
		push (@out, "</div>\n");
		push (@out, "<br>\n");
	}

	pop (@out);  # remove trailing <br>

	$self->write_report_thtml (%options, content => \@out);
}

sub write_report_thtml {
	my ($self, %options) = @_;

	my $producers = $self->producers;
	my $config = $self->config;
	my $webdir = $config->webdir;
	my $chain = $self->chain;
	my $lang = $options{lang};
	my $content = $options{content};
	my $outfile = $options{outfile};
	my $title = $options{title} || $config->label (key => "title_$outfile", lang => $lang);
	my @out;

	push (@out, "chain = $chain\n");
	push (@out, "title = %title_site%: $title\n");
	push (@out, "h1 = $title\n");
	push (@out, "\n");
	push (@out, @$content);

	write_file_atomic ($webdir . '/' . $chain . '/' . "$outfile.thtml.$lang", {binmode => ':utf8'}, @out);
}

sub sev_html {
	my ($self, %options) = @_;

	my $config = $self->config;
	my $webdir = $config->webdir;
	my $kind = $options{kind};
	my $class = $options{class};
	my $lang = $options{lang};
	my $color = $options{color};

	my $icons = $self->icons;
	my $html = $$icons{$kind} || encode_entities ($kind);
	if ($color) {
		$html = $$icons{"${kind}_${color}"} || encode_entities ($kind);
	}

	if ($class) {
		my $title = $config->label (key => "class_$class", lang => $lang);
		$html =~ s/ / title="$title" /;
	} else {
		my $title = $config->label (key => "$kind", lang => $lang);
		$html =~ s/ / title="$title" /;
	}

	return $html;
}

sub flag_html {
	my ($self, $alpha2) = @_;

	return "<span class=\"flag-icon flag-icon-$alpha2\"></span>";
}

sub generate_message {
	my ($self, $options, %params) = @_;

	my $config = $self->config;
	my $webdir = $config->webdir;
	my $content_type = $params{content_type} || die;
	my $lang = $params{lang} || die;

	my $service = $$options{service};
	my $feature = $$options{feature};
	my $count = $$options{count};
	my $value = $$options{value};
	my $value_time = $$options{value_time};
	my $suggested_value = $$options{suggested_value};
	my $delta_time = $$options{delta_time};
	my $request_timeout = $$options{request_timeout};
	my $cache_timeout = $$options{tls_cache_timeout} || $$options{cache_timeout};
	my $elapsed_time = $$options{elapsed_time};
	my $check_time = $$options{tls_check_time} || $$options{check_time};
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
	my $keybase_full_name = $$options{keybase_full_name};
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

	$request_timeout .= ' ' . $config->label (key => 'time_s', lang => $lang) if ($request_timeout);

	if ($cache_timeout) {
		$cache_timeout = undef if ($cache_timeout < 1800);
	}
	if ($cache_timeout) {
		if ($cache_timeout > 3600) {
			$cache_timeout = int ($cache_timeout / 3600);
			$cache_timeout .= ' ' . $config->label (key => 'time_h', lang => $lang);
		} else {
			$cache_timeout = int ($cache_timeout / 60);
			$cache_timeout .= ' ' . $config->label (key => 'time_m', lang => $lang);
		}
	}

	$elapsed_time = $self->format_elapsed_time (seconds => $elapsed_time, lang => $lang);
	$delta_time = $self->format_elapsed_time (seconds => $delta_time, lang => $lang);

	# ---------- output

	$detail .= $self->format_message_entry ('msg_service', $service, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_feature', $feature, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_threshold', $threshold, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_count', $count, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_value', $value, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_value_time', $config->datetime (timestring => $value_time, lang => $lang), 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_suggested_to_use_value', $suggested_value, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_delta_time', $delta_time, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_field', $field, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_contract', $contract, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_having_node_type', $node_type, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_resource', $resource, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_api_url', $api_url, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_url', $url, 1, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_post_data', $post_data, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_redirected_to_response_url', $response_url, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_response_from_host', $response_host, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_host', $host, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_ip', $ip, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_dns', $dns, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_port', $port, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_keybase_full_name', $keybase_full_name, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_keybase_location', $keybase_location, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_keybase_bio', $keybase_bio, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_elapsed_time', $elapsed_time, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_timeout', $request_timeout, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_validated_at', $config->datetime (timestring => $check_time, lang => $lang), 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_validated_every', $cache_timeout, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_explanation', $explanation, 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_see', $see1, 1, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_see', $see2, 1, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_last_updated_at', $config->datetime (timestring => $last_update_time, lang => $lang), 0, $content_type, $lang);
	$detail .= $self->format_message_entry ('msg_diff', $diff, 2, $content_type, $lang);

	return $detail;
}

sub format_elapsed_time {
	my ($self, %options) = @_;

	my $config = $self->config;
	my $webdir = $config->webdir;
	my $time = $options{seconds}; # $time is in seconds
	my $lang = $options{lang};

	return undef if (! defined $time);

	use integer;
	my $h = $time / 3600;
	my $m = $time / 60 % 60;
	my $s = $time % 60;

	if ($time > 3600) {
		return $h . ' ' . $config->label (key => 'time_h', lang => $lang) .  ' '
			. $m . ' ' . $config->label (key => 'time_m', lang => $lang) .  ' '
			. $s . ' ' . $config->label (key => 'time_s', lang => $lang);
	} elsif ($time > 60) {
		return $m . ' ' . $config->label (key => 'time_m', lang => $lang) .  ' '
			. $s . ' ' . $config->label (key => 'time_s', lang => $lang);
	} else {
		return $time . ' ' . $config->label (key => 'time_s', lang => $lang);
	}
}

sub format_message_entry {
	my ($self, $key, $value, $is_url, $content_type, $lang) = @_;

	my $config = $self->config;
	my $webdir = $config->webdir;

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
		return ', ' . $config->label (key => $key, lang => $lang) . '=&lt;' . $value . '&gt;';
	} else {
		if ($is_url == 2) {
			return "";
		} else {
			return ', ' . $config->label (key => $key, lang => $lang) . '=<' . $value .'>';
		}
	}
}

sub is_important_bp {
	my ($self, $entry) = @_;

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
	my ($self, $entry) = @_;

	my $logo = $$entry{output}{branding}{logo_256}[0]{address} || '';
	$logo = '' if ($logo !~ m#https://#);

	if ($logo) {
		$logo = "<figure class=\"image is-24x24\"><img src=\"$logo\"></figure>\n";
	} else {
		$logo = "<figure class=\"image is-24x24\"></figure>\n";
	}

	return $logo;
}

sub whois_org {
	my ($self, $node) = @_;

	my %orgs;

	foreach my $host (@{$$node{hosts}}) {
		my $org = $$host{organization};
		next if (! $org);
		$orgs{$org} = 1;
	}

	return join ('; ', sort keys %orgs);
}

sub whois_country {
	my ($self, $node) = @_;

	my %countries;

	foreach my $host (@{$$node{hosts}}) {
		my $country = $$host{country};
		next if (! $country);
		$countries{$country} = 1;
	}

	return join (' ', sort keys %countries);
}

sub whois_flag {
	my ($self, $node) = @_;

	my %countries;

	foreach my $host (@{$$node{hosts}}) {
		my $country = $$host{country};
		next if (! $country);
		$countries{$country} = 1;
	}

	return join (' ', map {$self->flag_html (lc ($_))} sort keys %countries);
}

1;
