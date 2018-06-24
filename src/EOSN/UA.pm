package EOSN::UA;

use utf8;
use strict;
use Exporter;
use LWP::UserAgent::Paranoid;
use JSON qw(from_json to_json);
use Data::Dumper;

use parent qw(Exporter);
our @EXPORT_OK = qw(eosn_ua get_table);

# ---------------------------------------------------------------------------
# Subroutines

sub eosn_ua {
	my $ua = new LWP::UserAgent::Paranoid;
	$ua->agent("curl/7.58.0");
	$ua->protocols_allowed(["http", "https"]);
	$ua->request_timeout(5);

	return $ua;
}

sub get_table {
	my ($ua, $url, %parameters) = @_;

	my $limit = $parameters{limit};
	$parameters{json} = JSON::true;

	my $more = "first";
	my $rows;

	while ($more) {
		#print ">> get table $url: ", to_json (\%parameters), "\n";
		my $req = HTTP::Request->new('POST', $url, undef, to_json (\%parameters));
		my $res = $ua->request($req);
		my $status_code = $res->code;
		my $status_message = $res->status_line;
		my $response_url = $res->request->uri;
	
		if (! $res->is_success) {
			warn "$0: cannot retrieve producers: $status_message";
			return undef;
		}

		my $content = $res->content;

		my $json;
		eval {
			$json = from_json ($content);
		};

		if ($@) {
			warn "$0: cannot retrieve producers: invalid json";
			return undef;
		}

		$rows = $$json{rows};
		$more = $$json{more};
		$parameters{more} = $more;

		#print ">> row count: ", scalar (@$rows), ", more: $more\n";

		last if (scalar @$rows >= $limit);
	}

	return $rows;
}

1;
