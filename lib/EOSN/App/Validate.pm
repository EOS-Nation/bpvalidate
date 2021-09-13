package EOSN::App::Validate;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use warnings;
use EOSN::Validate::Config;
use File::Slurp qw(read_file);
use Encode;

use parent qw(EOSN::App::Base);

# --------------------------------------------------------------------------
# Public Methods

sub run {
	my ($self) = @_;

	my $uri = $self->uri;
	my $lang = $self->lang;

	if ($uri =~ /\.html$/) {
		my $filename = $uri;
		$filename =~ s/\.html/.thtml.$lang/;
		return $self->generate_html_content (filename => $filename);

	} elsif ($uri =~ m#/$#) {
		my $filename = $uri;
		$filename .= "index.thtml.$lang";
		return $self->generate_html_content (filename => $filename);

	} elsif ($uri =~ m#/bps.json$#) {
		my $filename = $uri;
		return $self->generate_json_content (filename => $filename);

	} elsif ($uri =~ /\.json$/) {
		my $filename = $uri . '.' . $lang;
		return $self->generate_json_content (filename => $filename);

	} elsif ($uri =~ /\.txt$/) {
		my $filename = $uri . '.' . $lang;
		return $self->generate_txt_content (filename => $filename);
	}

	return $self->error_404;
}

# --------------------------------------------------------------------------
# Private Methods

sub generate_html_content {
	my ($self, %options) = @_;

	my $lang = $self->lang;
	my $webdir = $self->webdir;
	my $filename = $webdir . $options{filename};

	if (! -e $filename) {
		return $self->error_404;
	}

	#print "generate file from=<$filename_in> to=<$filename_out>\n";
	my (@content) = read_file ($filename, {binmode => ':utf8'});
	my $time = (stat ($filename))[9];

	my $content = $self->do_substitution (content => \@content, time => $time);
	my $output = $self->inject_footer (content => $content, lang => $lang);

	return [
		200,
		['Content-Type' => 'text/html; charset=UTF-8'],
		[encode_utf8 ($output)]
	];
}

sub generate_json_content {
	my ($self, %options) = @_;

	my $webdir = $self->webdir;
	my $filename = $webdir . $options{filename};

	if (! -e $filename) {
		return $self->error_404;
	}

	my $content = read_file ($filename, {binmode => ':utf8'});

	return [
		200,
		['Content-Type' => 'application/json; charset=UTF-8'],
		[encode_utf8 ($content)]
	];
}

sub generate_txt_content {
	my ($self, %options) = @_;

	my $webdir = $self->webdir;
	my $filename = $webdir . $options{filename};

	if (! -e $filename) {
		return $self->error_404;
	}

	my $content = read_file ($filename, {binmode => ':utf8'});

	return [
		200,
		['Content-Type' => 'text/plain; charset=UTF-8'],
		[encode_utf8 ($content)]
	];
}

sub do_substitution {
	my ($self, %options) = @_;

	my $time = $options{time};
	my $content = $options{content};
	my $lang = $self->lang;
	my $bpv_config = EOSN::Validate::Config->new;
	my $config = $self->config;
	my $globals = $$config{globals};
	my $labels = $$config{labels};
	my $generated = $$config{generated};
	my $variables = {};

	my $header = 1;
	my %variables;
	foreach my $line (@$content) {
		chomp ($line);
		if ($line =~ /^$/ && $header) {
			$header = 0;
		} elsif ($header) {
			my ($key, $value) = split (/\s*=\s*/, $line, 2);
			$$variables{$key} = $value;
		} else {
			$$variables{content} .= "$line\n";
		}
	}

	my $output = $$globals{template};
	$$globals{lang} = $lang;
	$$globals{last_update} = $self->datetime (unixtime => $time, lang => $lang);
	if ($$variables{chain}) {
		$$globals{chain_plain} = $$variables{chain};
		$$globals{chain} = $$labels{'chain_' . $$variables{chain}}{$lang} || $$variables{chain};
		$$globals{chain_title} = ($$labels{'chain_' . $$variables{chain}}{$lang} || $$variables{chain}) . ": ";
		$$generated{report_list} = $$generated{'report_list_' . $$variables{chain}};

		my $properties = $bpv_config->chain_properties ($$variables{chain});
		foreach my $key (qw (filename chain_id core_symbol)) {
			$$generated{"config_$key"} = $$properties{$key};
		}
		$$generated{maintainer} = '%maintainer_' . $$properties{maintainer} . '%';
	} else {
		$$globals{chain} = '--';
		$$globals{chain_title} = '';
	}

	foreach my $key (keys %$variables) {
		my $value = $$variables{$key};
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %$generated) {
		my $value = $$generated{$key};
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %$labels) {
		my $value = $$labels{$key}{$lang} || $$labels{$key}{en};
		if (! defined $value) {
			die "$0: cannot get label for key=<$key>\n";
		}
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %$globals) {
		my $value = $$globals{$key};
		$output =~ s/%$key%/$value/g;
	}	

	return $output;
}

1;
