package EOSN::UA;

use utf8;
use strict;
use Exporter;
use LWPx::ParanoidAgent;
use EOSN::CachingAgent;
use JSON qw(from_json to_json);
use Data::Dumper;

use parent qw(Exporter);
our @EXPORT_OK = qw(eosn_normal_ua eosn_cache_ua get_table);

# --------------------------------------------------------------------------
# Subroutines

sub eosn_normal_ua {
	my $ua = new LWPx::ParanoidAgent;
	#$ua->agent ('curl/7.64.0');
	$ua->agent ('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0');
	$ua->protocols_allowed (['http', 'https']);
	$ua->timeout (10);

	return $ua;
}

sub eosn_cache_ua {
	my $ua = new EOSN::CachingAgent;
	#$ua->agent ('curl/7.64.0');
	$ua->agent ('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:83.0) Gecko/20100101 Firefox/83.0');
	$ua->protocols_allowed (['http', 'https']);
	$ua->timeout (10);

	return $ua;
}

sub get_table {
	my ($ua, $url, %parameters) = @_;

	my $retry_count = 20;
	my $limit = $parameters{limit};
	$parameters{json} = JSON::true;

	my $more = 'first';
	my $rows;

	while ($more) {
		#print ">> get table $url: ", to_json (\%parameters), "\n";
		my $req = HTTP::Request->new('POST', $url, undef, to_json (\%parameters));
		my $res = $ua->request($req);
		my $status_code = $res->code;
		my $status_message = $res->status_line;
		my $response_url = $res->request->uri;
	
		if (! $res->is_success) {
			warn "$0: cannot retrieve table: $status_message";
			return undef;
		}

		my $content = $res->content;

		my $json;
		eval {
			$json = from_json ($content);
		};

		if ($@) {
			warn "$0: cannot retrieve table: invalid json";
			return undef;
		}

		$rows = $$json{rows};
		$more = $$json{more};
		$parameters{more} = $more;

		#print ">> row count: ", scalar (@$rows), ", more: $more\n";

		last if (scalar @$rows >= $limit);
		last if ($retry_count == 0);

		$retry_count--;
	}

	return $rows;
}

1;
