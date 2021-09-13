package EOSN::Middleware::Setup::Validate;

use utf8;
use strict;
use warnings;
use EOSN::Validate::Config;
use File::Slurp qw(read_dir read_file);

use parent qw(EOSN::Middleware::Setup::Base);

# --------------------------------------------------------------------------
# Preparation Methods

sub read_globals {
	my ($self) = @_;

	foreach my $host (keys %{$self->{config}}) {
		my $config = $self->{config}{$host};

		$self->set_template ($config);
		$self->set_maintainers ($config);
		$self->set_chain_info ($config);
	}
}

sub set_template {
	my ($self, $config) = @_;

	my $webdir = $$config{DocumentRoot};

	$$config{globals}{template} = read_file ("$webdir/res/template.html", {binmode => ':utf8'});
}

sub set_maintainers {
	my ($self, $config) = @_;

	my $webdir = $$config{DocumentRoot};

	foreach my $file (read_dir ("$webdir/res/maintainer")) {
		my ($maintainer, $lang) = (split (/\./, $file))[0,2];
		$$config{labels}{"maintainer_$maintainer"}{$lang} = read_file ("$webdir/res/maintainer/$file", {binmode => ':utf8'});
	}
}

sub set_chain_info {
	my ($self, $config) = @_;

	my $webdir = $$config{DocumentRoot};
	my $bpv_config = EOSN::Validate::Config->new;

	foreach my $chain ($bpv_config->chains) {
		my $properties = $bpv_config->chain_properties ($chain);

		# ---------- navigation

		$$config{generated}{navigation_producers} .= $self->nav_link ($chain, 'producers') . "\n";
		$$config{generated}{navigation_reports} .= $self->nav_link ($chain, 'reports') . "\n";
		$$config{generated}{navigation_info} .= $self->nav_link ($chain, 'info') . "\n";
		$$config{generated}{networks} .= (' ' x 4) . ' <li> <a href="' . $chain . '/"><img class="navbar-image" src="/res/chains/' . $chain . '.png" alt=""> %chain_' . $chain . '%</a>' . "\n";

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
			$$config{generated}{"report_list_$chain"} .= (' ' x 2) . '<li><a href="' . $report . '.html">%title_reports/' . $report . '%</a>' . "\n";
		}
	}
}

sub nav_link {
	my ($self, $chain, $url) = @_;

	return (' ' x 8) . '<a class="navbar-item" href="/' . $chain . '/' . $url . '/"><img class="navbar-image" src="/res/chains/' . $chain . '.png" alt=""> %chain_' . $chain . '%</a>';
}

# --------------------------------------------------------------------------
# Call Methods

1;
