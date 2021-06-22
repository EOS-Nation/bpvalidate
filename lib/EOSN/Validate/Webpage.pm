package EOSN::Validate::Webpage;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use YAML qw(LoadFile);

use parent qw(EOSN::Webpage);

# --------------------------------------------------------------------------
# Private Methods

sub initialize {
        my ($self) = @_;

	$self->SUPER::initialize;
	$self->read_chains;

        return $self;
}

# --------------------------------------------------------------------------
# Public Methods

sub read_chains {
        my ($self) = @_;

	$self->{chains} = LoadFile ($self->configdir . '/chains.yml');
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

1;
