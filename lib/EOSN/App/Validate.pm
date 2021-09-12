package EOSN::App::Validate;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use warnings;
use EOSN::Validate::Config;
use EOSN::Log qw(write_timestamp_log);
use Date::Format qw(time2str);
use File::Slurp qw(read_dir read_file);
use Plack::Builder;
use Plack::Request;
use Encode;

use parent qw(EOSN::App::Base);

# --------------------------------------------------------------------------
# Public Methods

sub prepare_app {
	my ($self) = @_;

	$self->SUPER::prepare_app ();

	$self->{config} = EOSN::Validate::Config->new;
	$self->read_globals ();
}

sub call {
	my ($self, $env) = @_;

        my $request = Plack::Request->new ($env);
        my $uri = $request->path_info;
	my $lang = $self->lang (env => $env);
	my $webdir = $self->webdir;

	if ($uri =~ /\.html$/) {
		my $filename = $uri;
		$filename =~ s/\.html/.thtml.$lang/;
		return $self->generate_html_content (lang => $lang, filename => $webdir . $filename);

	} elsif ($uri =~ m#/$#) {
		my $filename = $uri;
		$filename .= "index.thtml.$lang";
		return $self->generate_html_content (lang => $lang, filename => $webdir . $filename);

	} elsif ($uri =~ m#/bps.json$#) {
		my $filename = $uri;
		return $self->generate_json_content (lang => $lang, filename => $webdir . $filename);

	} elsif ($uri =~ /\.json$/) {
		my $filename = $uri . '.' . $lang;
		return $self->generate_json_content (lang => $lang, filename => $webdir . $filename);

	} elsif ($uri =~ /\.txt$/) {
		my $filename = $uri . '.' . $lang;
		return $self->generate_txt_content (lang => $lang, filename => $webdir . $filename);
	}

	return $self->error_404;
}

# ---------------------------------------------------------------------------
# Private Methods

sub read_globals {
	my ($self) = @_;

	my $webdir = $self->webdir;
	my $config = $self->{config};

	$self->{globals}{"template"} = read_file ("$webdir/res/template.html", {binmode => ':utf8'});
	$self->{labels} = $self->labels;

	foreach my $file (read_dir ("$webdir/res/maintainer")) {
		my ($maintainer, $lang) = (split (/\./, $file))[0,2];
		$self->{labels}{"maintainer_$maintainer"}{$lang} = read_file ("$webdir/res/maintainer/$file", {binmode => ':utf8'});
	}

        foreach my $chain ($config->chains) {
		my $properties = $config->chain_properties ($chain);

		# ---------- navigation

		$self->{generated}{navigation_producers} .= $self->nav_link ($chain, 'producers') . "\n";
		$self->{generated}{navigation_reports} .= $self->nav_link ($chain, 'reports') . "\n";
		$self->{generated}{navigation_info} .= $self->nav_link ($chain, 'info') . "\n";
		$self->{generated}{networks} .= (' ' x 4) . ' <li> <a href="' . $chain . '/"><img class="navbar-image" src="/res/chains/' . $chain . '.png" alt=""> %chain_' . $chain . '%</a>' . "\n";

		# --------- list of active reports

		my $xproperties;
                foreach my $property (keys %$properties) {
                        next if ($property !~ /^report_/);
                        next if (! $$properties{$property});
			$$xproperties{$property} = $$properties{$property};
		}
                foreach my $property (sort {$$xproperties{$a} <=> $$xproperties{$b}} keys %$xproperties) {
                        my $report = $property;
                        $report =~ s/^report_//;
			$self->{generated}{"report_list_$chain"} .= (' ' x 2) . '<li><a href="' . $report . '.html">%title_reports/' . $report . '%</a>' . "\n";
		}
	}
}

sub nav_link {
	my ($self, $chain, $url) = @_;

	return (' ' x 8) . '<a class="navbar-item" href="/' . $chain . '/' . $url . '/"><img class="navbar-image" src="/res/chains/' . $chain . '.png" alt=""> %chain_' . $chain . '%</a>';
}

sub generate_html_content {
	my ($self, %options) = @_;

	my $lang = $options{lang};
	my $filename = $options{filename};
	my $config = $self->{config};

	if (! -e $filename) {
		return $self->error_404;
	}

	#print "generate file from=<$filename_in> to=<$filename_out>\n";
	my (@content) = read_file ($filename, {binmode => ':utf8'});
	my $time = (stat ($filename))[9];

	my $header = 1;
	my %variables;
	foreach my $line (@content) {
		chomp ($line);
		if ($line =~ /^$/ && $header) {
			$header = 0;
		} elsif ($header) {
			my ($key, $value) = split (/\s*=\s*/, $line, 2);
			$variables{$key} = $value;
		} else {
			$variables{content} .= "$line\n";
		}
	}

	my $output = $self->{globals}{template};
	$self->{globals}{lang} = $lang;
	$self->{globals}{last_update} = $self->datetime (unixtime => $time, lang => $lang);
	if ($variables{chain}) {
		$self->{globals}{chain_plain} = $variables{chain};
		$self->{globals}{chain} = $self->{labels}{'chain_' . $variables{chain}}{$lang} || $variables{chain};
		$self->{globals}{chain_title} = ($self->{labels}{'chain_' . $variables{chain}}{$lang} || $variables{chain}) . ": ";
		$self->{generated}{report_list} = $self->{generated}{'report_list_' . $variables{chain}};

		my $properties = $config->chain_properties ($variables{chain});
		foreach my $key (qw (filename chain_id core_symbol)) {
			$self->{generated}{"config_$key"} = $$properties{$key};
		}
		$self->{generated}{maintainer} = '%maintainer_' . $$properties{maintainer} . '%';
	} else {
		$self->{globals}{chain} = '--';
		$self->{globals}{chain_title} = '';
	}

	foreach my $key (keys %variables) {
		my $value = $variables{$key};
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %{$self->{generated}}) {
		my $value = $self->{generated}{$key};
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %{$self->{labels}}) {
		my $value = $self->{labels}{$key}{$lang} || $self->{labels}{$key}{en};
		if (! defined $value) {
			die "$0: cannot get label for key=<$key>\n";
		}
		$output =~ s/%$key%/$value/g;
	}

	foreach my $key (keys %{$self->{globals}}) {
		my $value = $self->{globals}{$key};
		$output =~ s/%$key%/$value/g;
	}	

	$output = $self->inject_footer (content => $output, lang => $lang);

	return [
		200, 
		['Content-Type' => 'text/html; charset=UTF-8'],
		[encode_utf8 ($output)]
	];
}

sub generate_json_content {
	my ($self, %options) = @_;

	my $lang = $options{lang};
	my $filename = $options{filename};

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

	my $lang = $options{lang};
	my $filename = $options{filename};

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

1;
