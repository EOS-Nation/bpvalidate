package EOSN::UA;

# --------------------------------------------------------------------------
# Required modules

use utf8;
use strict;
use warnings;
use Exporter;
use LWPx::ParanoidAgent;
use EOSN::CachingAgent;

use parent qw(Exporter);
our @EXPORT_OK = qw(eosn_normal_ua eosn_cache_ua);

# --------------------------------------------------------------------------
# Subroutines

sub eosn_normal_ua {
	my $ua = LWPx::ParanoidAgent->new;
	#$ua->agent ('curl/7.64.0');
	$ua->agent ('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0');
	$ua->protocols_allowed (['http', 'https']);
	$ua->timeout (10);

	return $ua;
}

sub eosn_cache_ua {
	my $ua = EOSN::CachingAgent->new;
	#$ua->agent ('curl/7.64.0');
	$ua->agent ('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0');
	$ua->protocols_allowed (['http', 'https']);
	$ua->timeout (10);

	return $ua;
}

1;
