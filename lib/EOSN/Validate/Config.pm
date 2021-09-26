package EOSN::Validate::Config;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use warnings;
use Carp qw(confess);
use YAML qw(LoadFile);
use Date::Format qw(time2str);
use Date::Parse qw(str2time);

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
}

# --------------------------------------------------------------------------
# Private Methods

sub initialize {
	my ($self) = @_;

	$self->read_env;
	$self->read_strings;
	$self->read_chains;

	return $self;
}

# --------------------------------------------------------------------------
# Public Methods

sub read_env {
	my ($self) = @_;

	$self->{webdir} = $ENV{EOSN_WEBPAGE_WEB} || '/var/www/html';
	$self->{configdir} = $ENV{EOSN_WEBPAGE_CONFIG} || '/etc/page';
	$self->{default_lang} = $ENV{EOSN_WEBPAGE_LANG} || 'en';
}

sub read_chains {
	my ($self) = @_;

	$self->{chains} = LoadFile ($self->configdir . '/chains.yml');
}

sub read_strings {
	my ($self) = @_;

	my $labels = LoadFile ($self->configdir . '/language.yml');
	my %langs;

	foreach my $label (keys %$labels) {
		foreach my $lang (keys %{$$labels{$label}}) {
			$langs{$lang} = 1;
			#print sprintf ("label %20s %2s: %s\n", $label, $lang, ($$labels{$label}{$lang} || 'undef'));
		}
	}

	$self->{langs} = [sort keys %langs];
	$self->{labels} = $labels;
}


sub webdir {
	my ($self) = @_;

	return $self->{webdir};
}

sub configdir {
	my ($self) = @_;

	return $self->{configdir};
}

sub langs {
	my ($self) = @_;

	return @{$self->{langs}};
}

sub labels {
	my ($self) = @_;

	return $self->{labels};
}

sub label {
	my ($self, %options) = @_;

	my $lang = $options{lang} || confess "$0: lang not provided";
	my $key = $options{key} || confess "$0: key not provided";
	my $default_lang = $options{default_lang} || $self->{default_lang};
	my $labels = $self->labels;

	return $$labels{$key}{$lang} || $$labels{$key}{$default_lang} || "[$key]";
}

sub chains {
	my ($self) = @_;

	my $chains = $self->{chains};

	return sort {$$chains{$a}{sort_order} <=> $$chains{$b}{sort_order}} keys %$chains;
}

sub chain_properties {
	my ($self, $chain) = @_;

	return $self->{chains}{$chain};
}

sub content_types {
	return ('txt', 'json', 'html');
}

sub datetime {
	my ($self, %options) = @_;

	my $lang = $options{lang};
	my $unixtime = $options{unixtime};
	my $timestring = $options{timestring};

	if ($timestring) {
		 $unixtime = str2time ($timestring);
	}

	if (! $unixtime) {
		return '';
	}

	return time2str ($self->label (lang => $lang, key => 'format_datetime'), $unixtime, 'UTC');
}

1;
