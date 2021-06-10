package EOSN::BlockchainAPI;

use utf8;
use strict;
use Exporter;
use JSON qw(from_json to_json);

use parent qw(Exporter);
our @EXPORT_OK = qw(get_info get_table);

# --------------------------------------------------------------------------
# Subroutines

sub get_info {
	my ($ua, $url) = @_;

	#print ">> get info $url\n";
	my $req = HTTP::Request->new('GET', $url);
	my $res = $ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;

	if (! $res->is_success) {
		warn "$0: cannot retrieve info: $status_message";
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

	return $json;
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
