package EOSN::CachingAgent;

use utf8;
use strict;
use Carp qw(confess);
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(time);
use Date::Format qw(time2str);
use JSON;

use parent qw(LWPx::ParanoidAgent);

# --------------------------------------------------------------------------
# Subroutines

sub dbh {
	my ($self, $dbh) = @_;

	if ($dbh) {
		$self->{dbh} = $dbh;
	}

	return $self->{dbh};
}

sub options {
	my ($self, $options) = @_;

	if ($options) {
		$self->{options} = $options;
	}

	return $self->{options};
}

sub request {
	my ($self, $req, @args) = @_;

	my $dbh = $self->dbh;
	my $options = $self->options;
	my $sleep = 0;

	# --------- prepare the database

	if (! defined $dbh) {
		confess "$0: dbh not provided";
	}

	my $fetch = $dbh->prepare_cached ("select * from url where md5 = ?");
	my $insert = $dbh->prepare_cached ("insert into url (md5, checked_at, elapsed_time, request_method, request_url, request_headers, request_content, response_code, response_message, response_headers, response_content) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
	my $update = $dbh->prepare_cached ("update url set checked_at = ?, elapsed_time = ?, request_method = ?, request_url = ?, request_headers = ?, request_content = ?, response_code = ?, response_message = ?, response_headers = ?, response_content = ? where id = ?");

	# --------- check if the query has been executed recently

	my $request_string = join ('*', $req->method, $req->uri, join ('|', $req->headers->flatten), $req->content);
	my $md5 = md5_hex ($request_string);

	$fetch->execute ($md5);
	my $cache = $fetch->fetchrow_hashref;
	$fetch->finish;

	my $cache_timeout = $$options{cache_timeout};
	if (! defined $cache_timeout) {
		confess "$0: cache_timeout not provided";
	}

	if ($$options{cache_fast_fail} && $$cache{response_code}) {
		if ($$cache{response_code} != 200) {
			$cache_timeout = int($cache_timeout) / 28;
			print sprintf ("previous response_code=<%d>: cut cache by 28x to=<%d> for url=<%s> and wait 10s if requesting\n", $$cache{response_code}, $cache_timeout, $req->uri);
			$sleep = 20;
		}
	}

	if ($$cache{checked_at} && ($$cache{checked_at} > time - $cache_timeout)) {
		my $res = HTTP::Response->new($$cache{response_code}, $$cache{response_message}, from_json($$cache{response_headers}), $$cache{response_content});
		$res->request($req);
		$$options{elapsed_time} = sprintf ("%.1f", $$cache{elapsed_time});
		$$options{check_time} = time2str("%C", $$cache{checked_at});
		print sprintf ("c %.2f %3d %4s %s %s\n", $$cache{elapsed_time}, $$cache{response_code}, $req->method, $req->uri, $req->content);
		return $res;
	}

	# ---------- run the request

	my $clock = time;

	my $request_timeout = $$options{request_timeout} || confess "$0: timeout not provided";
	$self->timeout($request_timeout * 2);
	my $res = $self->SUPER::request($req, @args);

	my $elapsed_time = time - $clock;
	$$options{elapsed_time} = sprintf ("%.1f", $elapsed_time);
	$$options{check_time} = time2str("%C", $clock);
	print sprintf ("r %.2f %3d %4s %s %s\n", $elapsed_time, $res->code, $req->method, $req->uri, $req->content);

	# ---------- wait if needed to avoid overloading remote systems

	sleep ($sleep) if ($sleep);

	# ---------- update the database

	if ($$cache{id}) {
		$update->execute (time, $elapsed_time, $req->method, $req->url, to_json([$req->headers->flatten]), $req->content, $res->code, $res->message, to_json([$res->headers->flatten]), $res->content, $$cache{id});
	} else {
		$insert->execute ($md5, time, $elapsed_time, $req->method, $req->url, to_json([$req->headers->flatten]), $req->content, $res->code, $res->message, to_json([$res->headers->flatten]), $res->content);
	}

	return $res;
}

1;
