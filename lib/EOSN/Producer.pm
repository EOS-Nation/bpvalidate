package EOSN::Producer;

use utf8;
use strict;
use JSON;
use EOSN::UA qw(eosn_ua get_table);
use Locale::Country;
use Data::Validate qw(is_integer is_numeric is_between);
use Data::Validate::IP qw(is_public_ip);
use IO::Socket;
use Data::Dumper;
use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Carp qw(confess);
use Time::Seconds;

our %content_types;
$content_types{json} = ['application/json'];
$content_types{png_jpg} = ['image/png', 'image/jpeg'];
$content_types{svg} = ['image/svg+xml'];
$content_types{html} = ['text/html'];

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
	$self->{versions} = undef;
	$self->{dbh} = undef;
	$self->{ua} = undef;
	$self->{properties} = undef;
	$self->{messages} = undef;
	$self->{urls} = undef;
}

# --------------------------------------------------------------------------
# Private Methods

sub initialize {
	my ($self, %attributes) = @_;

	foreach my $key (keys %attributes) {
		$self->{$key} = $attributes{$key};
	}

	return $self;
}

# --------------------------------------------------------------------------
# Get/Set Public Methods

sub properties {
	my ($self, $properties) = @_;

	if ($properties) {
		$self->{properties} = $properties;
	}

	return $self->{properties};
}

sub messages {
	my ($self, $messages) = @_;

	if ($messages) {
		$self->{messages} = $messages;
	}

	return $self->{messages};
}

sub results {
	my ($self, $results) = @_;

	if ($results) {
		$self->{results} = $results;
	}

	return $self->{results};
}

sub ua {
	my ($self, $ua) = @_;

	if ($ua) {
		$self->{ua} = $ua;
	}

	return $self->{ua};
}

sub dbh {
	my ($self, $dbh) = @_;

	if ($dbh) {
		$self->{dbh} = $dbh;
	}

	return $self->{dbh};
}

sub versions {
	my ($self, $versions) = @_;

	if ($versions) {
		$self->{versions} = $versions;
	}

	return $self->{versions};
}

# --------------------------------------------------------------------------
# Accesor Public Methods

sub name {
	my ($self) = @_;

	return $self->{properties}{owner};
}

# --------------------------------------------------------------------------
# Validate Public Methods

sub validate {
	my ($self) = @_;

	$self->{results}{regproducer} = $self->{properties};

	my $start_time = time;
	$self->run_validate;
	my $end_time = time;

	$self->{results}{messages} = $self->messages;
	$self->{results}{meta}{generated_at} = time2str("%C", time);
	$self->{results}{meta}{elapsed_time} = $end_time - $start_time;

	return $self->{results};
}

sub run_validate {
	my ($self) = @_;

	my $name = $self->{properties}{owner};
	my $key = $self->{properties}{producer_key};
	my $url = $self->{properties}{url};
	my $is_active = $self->{properties}{is_active};

	if (! $is_active) {
		$self->add_message(kind => 'skip', detail => 'producer is not active');
		return undef;
	}

	#print ">> [$name][$key][$url][$votes]\n";

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message(kind => 'crit', detail => 'invalid configured url', url => $url);
		return undef;
	}

	$self->validate_url("$url", 'main web site', content_type => 'html', cors => 'either', dupe => 'skip', add_to_list => 'resources/regproducer_url');

	my $json = $self->validate_url("$url/bp.json", 'bp info json url', content_type => 'json', cors => 'should', dupe => 'err', add_to_list => 'resources/bpjson');
	return undef if (! $json);

	$self->{results}{input} = $json;

	# ---------- check basic things

	if (! ref $$json{org}) {
		$self->add_message(kind => 'err', detail => 'not a object', field => 'org');
		return undef;
	}	
	if (! ref $$json{org}{location}) {
		$self->add_message(kind => 'err', detail => 'not a object', field =>'org.location');
		return undef;
	}
	$self->validate_string($$json{org}{location}{name}, 'org.location.name');
	$self->validate_string($$json{org}{location}{country}, 'org.location.country');
	$self->validate_string($$json{org}{location}{latitude}, 'org.location.latitude');
	$self->validate_string($$json{org}{location}{longitude}, 'org.location.longitude');
	$self->validate_string($$json{org}{candidate_name}, 'org.candidate_name');
	$self->validate_string($$json{org}{email}, 'org.email');
	$self->validate_string($$json{producer_public_key}, 'producer_public_key');
	$self->validate_string($$json{producer_account_name}, 'producer_account_name');
	$self->validate_country($$json{org}{location}{country}, 'org.location.country');

	if ($$json{producer_public_key} && $$json{producer_public_key} ne $key) {
		$self->add_message(kind => 'crit', detail => 'no match between bp.json and regproducer', field => 'producer_public_key');
	}

	if ($$json{producer_account_name} && $$json{producer_account_name} ne $name) {
		$self->add_message(kind => 'crit', detail => 'no match between bp.json and regproducer', field => 'producer_account_name');
	}

	$self->validate_url($$json{org}{website}, 'org.website', content_type => 'html', add_to_list => 'resources/website', dupe => 'warn');
	$self->validate_url($$json{org}{code_of_conduct}, 'org.code_of_conduct', content_type => 'html', add_to_list => 'resources/conduct', dupe => 'warn');
	$self->validate_url($$json{org}{ownership_disclosure}, 'org.ownership_disclosure', content_type => 'html', add_to_list => 'resources/ownership', dupe => 'warn');
	$self->validate_url($$json{org}{branding}{logo_256}, 'org.branding.logo_256', content_type => 'png_jpg', add_to_list => 'resources/social_logo_256', dupe => 'warn');
	$self->validate_url($$json{org}{branding}{logo_1024}, 'org.branding.logo_1024', content_type => 'png_jpg', add_to_list => 'resources/social_logo_1024', dupe => 'warn');
	$self->validate_url($$json{org}{branding}{logo_svg}, 'org.branding.logo_svg', content_type => 'svg', add_to_list => 'resources/social_logo_svg', dupe => 'warn');

	foreach my $key (sort keys %{$$json{org}{social}}) {
		my $value = $$json{org}{social}{$key};
		if ($value =~ m#https?://#) {
			$self->add_message(kind => 'err', detail => 'social media references must be relative', field => "org.social.$key");
		}
	}

	# ---------- check nodes

	if (! ref $$json{nodes}) {
		$self->add_message(kind => 'err', detail => 'not a object', field => 'nodes');
		return undef;
	}	

	my @nodes;
	eval {
		@nodes = @{$$json{nodes}};
	};

	my $node_number = 0;
	my $api_endpoint;
	my $peer_endpoint;
	foreach my $node (@nodes) {
		my $found_something = 0;
		my $location = $self->validate_location($$node{location}, "node[$node_number].location");
		my $node_type = $$node{node_type};

		# ---------- check type of node

		if ($$node{is_producer}) {
			$self->add_message(kind => 'warn', detail => "is_producer is deprecated use instead 'node_type' with one of the following values ['producer', 'full', 'query']", field => "node[$node_number].is_producer");
			if ($$node{is_producer} && (! exists $$node{node_type})) {
				$node_type = 'producer';
				$$node{node_type} = 'producer'; # set this to avoid the error message below
			}
		}

		if ((! exists $$node{node_type}) || (! defined $$node{node_type})) {
			$self->add_message(kind => 'warn', detail => "node_type is not provided, set it to one of the following values ['producer', 'full', 'query']", field => "node[$node_number");
		} elsif (($$node{node_type} ne 'producer') && ($$node{node_type} ne 'full') && ($$node{node_type} ne 'query')) {
			$self->add_message(kind => 'err', detail => "node_type is not valid, set it to one of the following values ['producer', 'full', 'query']", field => "node[$node_number].node_type");
		} else {
			$node_type = $$node{node_type};
		}

		# ---------- check endpoints

		if ((defined $$node{api_endpoint}) && ($$node{api_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api($$node{api_endpoint}, "node[$node_number].api_endpoint", ssl => 'off', add_to_list => 'nodes/api_http', node_type => $node_type, location => $location);
			if ($result) {
				$api_endpoint++;
			}
		}

		if ((defined $$node{ssl_endpoint}) && ($$node{ssl_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api($$node{ssl_endpoint}, "node[$node_number].ssl_endpoint", ssl => 'on', add_to_list => 'nodes/api_https', node_type => $node_type, location => $location);
			if ($result) {
				$api_endpoint++;
			}
		}

		if ((defined $$node{p2p_endpoint}) && ($$node{p2p_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection($$node{p2p_endpoint}, "node[$node_number].p2p_endpoint", connection_type => 'p2p', add_to_list => 'nodes/p2p', node_type => $node_type, location => $location)) {
				$peer_endpoint++;
			}
		}

		if ((defined $$node{bnet_endpoint}) && ($$node{bnet_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection($$node{bnet_endpoint}, "node[$node_number].bnet_endpoint", connection_type => 'bnet', add_to_list => 'nodes/bnet', node_type => $node_type, location => $location)) {
				$peer_endpoint++;
			}
		}

		# ---------- check if something was found and compare to node type

		if (! defined $node_type) {
			# cannot check
		} elsif ($node_type eq 'producer') {
			if ($found_something) {
				$self->add_message(kind => 'warn', detail => 'endpoints provided (producer should be private)', field => "node[$node_number]");
			}
		} else {
			if (! $found_something) {
				$self->add_message(kind => 'warn', detail => 'no endpoints provided (useless section)', field => "node[$node_number]");
			}
		}
			
		$node_number++;
	}

	if (! $api_endpoint) {
		$self->add_message(kind => 'crit', detail => 'no API endpoints provided (that do not have errors noted) of either api_endpoint or ssl_endpoint');
	}
	if (! $peer_endpoint) {
		$self->add_message(kind => 'crit', detail => 'no P2P or BNET endpoints provided (that do not have errors noted)');
	}
}

sub validate_string {
	my ($self, $string, $type) = @_;

	if (! $string) {
		$self->add_message(kind => 'err', detail => 'no value given', field => $type);
		return undef;
	}

	return 1;
}

sub validate_url {
	my ($self, $url, $type, %options) = @_;

	my $content_type = $options{content_type} || confess "content_type not provided";
	my $ssl = $options{ssl} || 'either'; # either, on, off
	my $cors = $options{cors} || 'either'; #either, on, off, should
	my $url_ext = $options{url_ext} || '';
	my $non_standard_port = $options{non_standard_port}; # true/false
	my $dupe = $options{dupe} || confess "dupe checking not specified"; # err or warn or crit or skip
	my $timeout = $options{timeout} || 10;

	#print ">> check url=[GET $url$url_ext]\n";

	if (! $url) {
		$self->add_message(kind => 'err', detail => "no url given", field => $type);
		return undef;
	}

	if ($dupe ne 'skip') {
		if ($self->{urls}{$url}) {
			$self->add_message(kind => $dupe, detail => "duplicate url", field => $type, url => $url);
			return undef if ($dupe eq 'err');
		}
		$self->{urls}{$url} = 1;
	}

	$url =~ s/#.*$//;

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message(kind => 'err', detail => "invalid url", url => $url, field => $type);
		return undef;
	}
	if ($url =~ m#^https?://.*//#) {
		$self->add_message(kind => 'warn', detail => "double slashes", url => $url, field => $type);
		$url =~ s#(^https?://.*)//#$1/#;
	}
	if ($url =~ m#^https?://localhost#) {
		$self->add_message(kind => 'err', detail => "localhost", url => $url, field => $type);
		return undef;
	}
	if ($url =~ m#^https?://127\.#) {
		$self->add_message(kind => 'err', detail => "localhost", url => $url, field => $type);
		return undef;
	}

	my $host_port;
	my $protocol;
	my $location;
	if ($url =~ m#^(https?)://(.*?)(/.*)$#) {
		$protocol = $1;
		$host_port = $2;
		$location = $3;
	} elsif ($url =~ m#^(https?)://(.*)$#) {
		$protocol = $1;
		$host_port = $2;
	} else {
		confess "cannot determine host name";
	}

	#print ">> [$host_port]\n";
	my ($host, $port) = split (/:/, $host_port, 2);

	if (defined $port) {
		if (! $self->validate_port($port, $type)) {
			return undef;
		}
	}

	if ($protocol eq 'http' && $port && $port == 80) {
		$self->add_message(kind => 'warn', detail => "port is not required", url => $url, port => 80, field => $type);
	} elsif ($protocol eq 'https' && $port && $port == 443) {
		$self->add_message(kind => 'warn', detail => "port is not required", url => $url, port => 443, field => $type);
	}
	if ($non_standard_port) {
		if ($protocol eq 'http' && $port && $port != 80) {
			$self->add_message(kind => 'info', detail => "port is non-standard (not using 80) and may be unusable by some applications", url => $url, port => $port, field => $type);
		} elsif ($protocol eq 'https' && $port && $port != 443) {
			$self->add_message(kind => 'info', detail => "portis non-standard (not using 443) and may be unusable by some applications", url => $url, port => $port, field => $type);
		}
	}
	if ($location && $location eq '/') {
		$self->add_message(kind => 'warn', detail => "trailing slash is not required", url => $url, field => $type);
	}

	if (! $self->validate_ip_dns($host, $type)) {
		return undef;
	}	

	if ($ssl eq 'either') {
		if ($url !~ m#^https://#) {
			$self->add_message(kind => 'warn', detail => "consider using HTTPS instead of HTTP", url => $url, field => $type);
		}
	} elsif ($ssl eq 'on') {
		if ($url !~ m#^https://#) {
			$self->add_message(kind => 'err', detail => "need to specify HTTPS instead of HTTP", url => $url, field => $type);
			return undef;
		}
	} elsif ($ssl eq 'off') {
		if ($url =~ m#^https://#) {
			$self->add_message(kind => 'err', detail => "need to specify HTTP instead of HTTPS", url => $url, field => $type);
			return undef;
		}
	} else {
		confess "unknown ssl option";
	}

	my $req = HTTP::Request->new('GET', $url . $url_ext);
	$req->header('Origin', 'https://example.com');
	$self->ua->timeout($timeout);
	my $res = $self->ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_content_type = $res->content_type;

	if (! $res->is_success) {
		$self->add_message(kind => 'crit', detail => "invalid url message=<$status_message>", url => $url, field => $type);
		return undef;
	}

	if ($options{api_checks}) {
		my $server_header = $res->header('Server');
		if ($server_header && $server_header =~ /cloudflare/) {
			$self->add_message(kind => 'info', detail => "cloudflare restricts some client use making this endpoint not appropriate for some use cases", url => $url, field => $type);
		}

		my $cookie_header = $res->header('Set-Cookie');
		if ($cookie_header) {
			$self->add_message(kind => 'err', detail => "API nodes must not set cookies", url => $url, field => $type);
			return undef;
		}

		if ($ssl eq 'on') {
			# LWP doesn't seem to support HTTP2, so make an extra call
			my $check_http2 = `curl '$url$url_ext' --verbose --max-time 1 --stderr -`;
			if ($check_http2 =~ m#HTTP/2 200#) {
				$options{add_to_list} .= '2';
			} else {
				$self->add_message(kind => 'warn', detail => "HTTPS API nodes would have better performance by using HTTP/2", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages');
			}
		}
	}

	my @cors_headers = $res->header('Access-Control-Allow-Origin');
	if ($cors eq 'either') {
		# do nothing
	} elsif ($cors eq 'should') {
		# error, but not fatal, but not ok either
		if (! @cors_headers) {
			$self->add_message(kind => 'err', detail => "missing Access-Control-Allow-Origin header", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		} elsif (@cors_headers > 1) {
			$self->add_message(kind => 'err', detail => "multiple Access-Control-Allow-Origin headers=<@cors_headers>", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		} elsif ($cors_headers[0] ne '*') {
			$self->add_message(kind => 'err', detail => "inappropriate Access-Control-Allow-Origin header=<@cors_headers>", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		}	
	} elsif ($cors eq 'on') {
		if (! @cors_headers) {
			$self->add_message(kind => 'err', detail => "missing Access-Control-Allow-Origin header", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		} elsif (@cors_headers > 1) {
			$self->add_message(kind => 'err', detail => "multiple Access-Control-Allow-Origin headers=<@cors_headers>", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		} elsif ($cors_headers[0] ne '*') {
			$self->add_message(kind => 'err', detail => "inappropriate Access-Control-Allow-Origin header=<@cors_headers>", url => $url, field => $type, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		}	
	} elsif ($cors eq 'off') {
		if (@cors_headers) {
			$self->add_message(kind => 'err', detail => "Access-Control-Allow-Origin header returned when should not be", url => $url, field => $type);
			return undef;
		}	
	} else {
		confess "unknown cors option";
	}

	if (! $response_content_type) {
		$self->add_message(kind => 'err', detail => "did not receive content_type header", url => $url, field => $type);
		return undef;
	} elsif ($content_type && $content_types{$content_type}) {
		my $found = 0;
		foreach my $x (@{$content_types{$content_type}}) {
			$found = 1 if ($x eq $response_content_type);
		}
		if (! $found) {
			$self->add_message(kind => 'err', detail => "received unexpected content_type=<$response_content_type>", url => $url, field => $type);
			return undef;
		}
	}

	my $content = $res->content;

	if ($response_url ne ($url . $url_ext)) {
		$self->add_message(kind => 'info', detail => "url redirected", url => $url, field => $type, response_url => '' .$response_url);
		if ($ssl eq 'on') {
			if ($response_url !~ m#^https://#) {
				$self->add_message(kind => 'err', detail => "need to specify HTTPS instead of HTTP", url => $url, field => $type, response_url => '' . $response_url);
				return undef;
			}
		} elsif ($ssl eq 'off') {
			if ($response_url =~ m#^https://#) {
				$self->add_message(kind => 'err', detail => "need to specify HTTP instead of HTTPS", url => $url, field => $type, response_url => '' . $response_url);
				return undef;
			}
		}
	}

	my $json;
	if ($content_type eq 'json') {
		#printf ("%v02X", $content);
		if ($content =~ /^\xEF\xBB\xBF/) {
			$self->add_message(kind => 'err', detail => "remove BOM (byte order mark) from start of json", url => $url, field => $type);
			$content =~ s/^\xEF\xBB\xBF//;
		}			
		eval {
			$json = from_json ($content, {utf8 => 1});
		};

		if ($@) {
			my $message = $@;
			chomp ($message);
			$message =~ s# at /usr/share/perl5/JSON.pm.*$##;
			$self->add_message(kind => 'err', detail => "invalid json error=<$message>", url => $url, field => $type);
			#print $content;
			return undef;
		}
	} elsif ($content_type eq 'png_jpg') {
	} elsif ($content_type eq 'svg') {
	} elsif ($content_type eq 'html') {
	}

	my $return;
	if ($json) {
		$return = $json;
	} else {
		$return = $res;
	}

	my $info;
	if ($options{extra_check}) {
		my $function = $options{extra_check};
		$info = $self->$function ($return, $url, $type, %options);
		if (! $info) {
			return undef;
		}
	}

	$self->add_to_list($url, $type, info => $info, result => $json, %options) if ($options{add_to_list});

	return $return;
}

sub validate_connection {
	my ($self, $peer, $type, %options) = @_;

	#print ">> peer=[$peer]\n";

	if ($self->{urls}{$peer}) {
		$self->add_message(kind => 'err', detail => "duplicate peer", field => $type, host => $peer);
		return undef;
	}
	$self->{urls}{$peer} = 1;

	if ($peer =~ m#^https?://#) {
		$self->add_message(kind => 'err', detail => "peer cannot begin with http(s)://", field => $type, host => $peer);
		return undef;
	}		

	my $connection_type = $options{connection_type};

	my $host;
	my $port;

	if ($peer =~ /^\[/) {
		# IPv6 address
		($host, $port) = split (/\]:/, $peer);
		$host =~ s/^\[//;
	} else {
		($host, $port) = split (/:/, $peer);
	}

	$port = $self->validate_port ($port, $type);
	if (! $port) {
		return undef;
	}

	$host = $self->validate_ip_dns ($host, $type);
	if (! $host) {
		return undef;
	}

	#print ">> check connection to [$host]:[$port]\n";
	my $sh = new IO::Socket::INET (PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
	if (! $sh) {
		$self->add_message(kind => 'err', detail => "cannot connect to peer", field => $type, host => $host, port => $port);
		return undef;
	}	
	close ($sh);

	$self->add_to_list($peer, $type, %options) if ($options{add_to_list});

	return 1;
}

sub validate_api {
	my ($self, $url, $type, %options) = @_;

	return $self->validate_url($url, $type,
		url_ext => '/v1/chain/get_info',
		content_type => 'json',
		cors => 'on',
		api_checks => 'on',
		non_standard_port => 1,
		extra_check => 'validate_api_extra_check',
		add_result_to_list => 'response',
		add_info_to_list => 'info',
		dupe => 'err',
		timeout => 3,
		%options
	);
}

sub validate_api_extra_check {
	my ($self, $result, $url, $type, %options) = @_;

	my %info;
	my $errors;
	my $versions = $self->versions;

	if (! $$result{chain_id}) {
		$self->add_message(kind => 'crit', detail => 'cannot find chain_id in response', url => $url, field => $type);
		$errors++;
	}

	if ($$result{chain_id} ne 'aca376f206b8fc25a6ed44dbdc66547c36c6c33e3a119ffbeaef943642f0e906') {
		$self->add_message(kind => 'crit', detail => "invalid chain_id=<$$result{chain_id}>", url => $url, field => $type);
		$errors++;
	}


	if (! $$result{head_block_time}) {
		$self->add_message(kind => 'crit', detail => 'cannot find head_block_time in response', url => $url, field => $type);
		$errors++;
	}

	my $time = str2time($$result{head_block_time} . ' UTC');
	my $delta = abs(time - $time);
	
	if ($delta > 10) {
		my $val = Time::Seconds->new($delta);
		my $deltas = $val->pretty;
		#$self->add_message(kind => 'crit', detail => "last block is not up-to-date with timestamp=<$$result{head_block_time}> delta=<$deltas>", url => $url, field => $type);
		$self->add_message(kind => 'crit', detail => "last block is not up-to-date with timestamp=<$$result{head_block_time}>", url => $url, field => $type);
		$errors++;
	}

	if (! $$result{server_version}) {
		$self->add_message(kind => 'crit', detail => "cannot find server_version in response; contact \@mdarwin on telegram and provide the information", url => $url, field => $type);
		$errors++;
	}

	if (! $$versions{$$result{server_version}}) {
		$self->add_message(kind => 'warn', detail => "unknown server version=<$$result{server_version}> in response", url => $url, field => $type);
	} else {
		my $name = $$versions{$$result{server_version}}{name};
		my $current = $$versions{$$result{server_version}}{current};
		$info{server_version} = $name;
		if (! $current) {
			$self->add_message(kind => 'warn', detail => "server version=<$name> is out of date in response", url => $url, field => $type);
		}
	}

	if (! $self->test_patreonous ($url, $type)) {
		$errors++;
	}

	if ($errors) {
		return undef;
	}

	return \%info;
}

sub validate_port {
	my ($self, $port, $type) = @_;

	if (! defined $port) {
		$self->add_message(kind => 'crit', detail => 'port is not provided', field => $type);
		return undef;
	}
	if (! defined is_integer ($port)) {
		$self->add_message(kind => 'crit', detail => 'port is not a valid integer', field => $type, port => $port);
		return undef;
	}
	if (! is_between ($port, 1, 65535)) {
		$self->add_message(kind => 'crit', detail => 'port is not a valid integer in range 1 to 65535', field => $type, port => $port);
		return undef;
	}

	return $port;
}

sub validate_ip_dns {
	my ($self, $host, $type) = @_;

	if (($host =~ /^[\d\.]+$/) || ($host =~ /^[\d\:]+$/)) {
		$self->add_message(kind => 'warn', detail => 'better to use DNS names instead of IP address', field => $type, host => $host);
		return $self->validate_ip($host, $type);
	} else {
		return $self->validate_dns($host, $type);
	}
}

sub validate_ip {
	my ($self, $ip, $type) = @_;

	if (! is_public_ip($ip)) {
		$self->add_message(kind => 'crit', detail => 'not a valid ip address', field => $type, ip => $ip);
		return undef;
	}

	return $ip;
}

sub validate_dns {
	my ($self, $value, $type) = @_;

	#my ($name, $aliases, $addrtype, $length, @addrs) = gethostbyname($value);
	my $addr = gethostbyname($value);
	if ($addr) {
		my ($a,$b,$c,$d) = unpack('C4',$addr);
		$value = "$a.$b.$c.$d";
		return $self->validate_ip($value, $type);
	} else {
		$self->add_message(kind => 'crit', detail => 'cannot resolve DNS name', field => $type, dns => $value);
		return undef;
	}
}

sub validate_location {
	my ($self, $location, $type) = @_;

	my $country = $self->validate_country($$location{country}, $type);
	my $name = $$location{name};
	my $latitude = is_numeric ($$location{latitude});
	my $longitude = is_numeric ($$location{longitude});

	if (! defined $name) {
		$self->add_message(kind => 'err', detail => 'no name', field => $type);
		$name = undef;
	} elsif ($name eq $self->name) {
		$self->add_message(kind => 'err', detail => 'same name as producer, should be name of location', field => $type);
		$name = undef;
	}

	if (! defined $latitude) {
		$self->add_message(kind => 'err', detail => 'no valid latitude', field => $type);
	}
	if (! defined $longitude) {
		$self->add_message(kind => 'err', detail => 'no valid longitude', field => $type);
	}
	if ((! defined $latitude) || (! defined $longitude)) {
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $latitude) && ($latitude > 90 || $latitude < -90)) {
		$self->add_message(kind => 'err', detail => 'latitude out of range', field => $type);
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $longitude) && ($longitude > 180 || $longitude < -180)) {
		$self->add_message(kind => 'err', detail => 'longitude out of range', field => $type);
		$latitude = undef;
		$longitude = undef;
	}
	if (defined $latitude && defined $longitude && $latitude == 0 && $longitude == 0) {
		$self->add_message(kind => 'err', detail => 'latitude,longitude is 0,0', field => $type);
		$latitude = undef;
		$longitude = undef;
	}

	my %return;
	$return{country} = $country if (defined $country);
	$return{name} = $name if (defined $name);
	$return{latitude} = $latitude if (defined $latitude);
	$return{longitude} = $longitude if (defined $longitude);

	return \%return;
}

sub validate_country {
	my ($self, $country, $type) = @_;

	if ($country && $country !~ /^[A-Z]{2}$/) {
		$self->add_message(kind => 'err', detail => 'not exactly 2 uppercase letters', field => $type);
		return undef;
	} elsif (! code2country($country)) {
		$self->add_message(kind => 'err', detail => 'not a valid 2 letter country code', field => $type);
		return undef;
	}

	return $country;
}

sub test_patreonous {
	my ($self, $base_url, $type) = @_;
	my $url = "$base_url/v1/chain/get_table_rows";

	my $req = HTTP::Request->new('POST', $url, undef, '{"scope":"eosio", "code":"eosio", "table":"global", "json": true}');
	my $res = $self->ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;

	if (! $res->is_success) {
		$self->add_message(kind => 'crit', detail => "invalid patreonous filter message=<$status_message>", field => $type, url => $url, explanation => 'https://github.com/EOSIO/patroneos/issues/36');
		return undef;
	}

	return 1;
}

sub add_message {
	my ($self, %options) = @_;
	
	my $kind = $options{kind} || confess "missing kind";
	my $detail = $options{detail} || confess "missing detail";

	push (@{$self->{messages}}, \%options);
}

sub add_to_list {
	my ($self, $host, $type, %options) = @_;

	my ($section, $list) = split (m#/#, $options{add_to_list});

	# make the display nicer

	if ($host =~ m#(http://.*):80$#) {
		$host = $1;
	} elsif ($host =~ m#(https://.*):443$#) {
		$host = $1;
	}

	my %data;
	$data{address} = $host;

	if ($options{add_result_to_list} && $options{result}) {
		my $key = $options{add_result_to_list};
		my $result = $options{result};
		$data{$key} = $result;
	}
	if ($options{add_info_to_list} && $options{info}) {
		my $key = $options{add_info_to_list};
		my $info = $options{info};
		$data{$key} = $info;
	}
	if ($options{location}) {
		$data{location} = $options{location};
	}
	if ($options{node_type}) {
		$data{node_type} = $options{node_type};
	}

	push (@{$self->{results}{output}{$section}{$list}}, \%data);

	$self->add_message(kind => 'ok', detail => 'basic checks passed', resource => $options{add_to_list}, url => $host, type => $type);
}

1;
