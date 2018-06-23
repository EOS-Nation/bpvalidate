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
use Date::Parse qw(str2time);
use Time::Seconds;

our %content_types;
$content_types{json} = ['application/json'];
$content_types{png_jpg} = ['image/png', 'image/jpeg'];
$content_types{svg} = ['image/svg+xml'];

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

	$self->{results}{regproduce} = $self->{properties};

	$self->run_validate;

	if (! $self->{messages}) {
		$self->add_message('ok', "checks passed");
	}
	$self->{results}{messages} = $self->messages;

	return $self->{results};
}

sub run_validate {
	my ($self) = @_;

	my $name = $self->{properties}{owner};
	my $key = $self->{properties}{producer_key};
	my $url = $self->{properties}{url};
	my $is_active = $self->{properties}{is_active};

	if (! $is_active) {
		$self->add_message('skip', "producer is not active");
		return undef;
	}

	#print ">> [$name][$key][$url][$votes]\n";

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message('err', "invalid configured url for url=<$url>");
		return undef;
	}

	my $json = $self->validate_url("$url/bp.json", "bp info json url", content_type => 'json', cors => 'should', add_to_list => 'resources/bpjson');
	return undef if (! $json);

	$self->{results}{input} = $json;

	# ---------- check basic things

	my $error = 0;
	if (! ref $$json{org}) {
		$self->add_message('err', "field=<org> is not a object");
		return undef;
	}	
	if (! ref $$json{org}{location}) {
		$self->add_message('err', "field=<org.location> is not a object");
		return undef;
	}
	$self->validate_string($$json{org}{location}{name}, 'org.location.name') || $error++;
	$self->validate_string($$json{org}{location}{country}, 'org.location.country') || $error++;
	$self->validate_string($$json{org}{location}{latitude}, 'org.location.latitude') || $error++;
	$self->validate_string($$json{org}{location}{longitude}, 'org.location.longitude') || $error++;
	$self->validate_string($$json{org}{candidate_name}, 'org.candidate_name') || $error++;
	$self->validate_string($$json{org}{email}, 'org.email') || $error++;
	$self->validate_string($$json{producer_public_key}, 'producer_public_key') || $error++;
	$self->validate_string($$json{producer_account_name}, 'producer_account_name') || $error++;

	if (! $self->validate_country($$json{org}{location}{country}, 'org.location.country')) {
		$error++;
	}

	if ($$json{producer_public_key} && $$json{producer_public_key} ne $key) {
		$error++;
		$self->add_message('err', "field=<producer_public_key> does not match between bp.json and regproducer");
	}

	if ($$json{producer_account_name} && $$json{producer_account_name} ne $name) {
		$error++;
		$self->add_message('err', "field=<producer_account_name> does not match between bp.json and regproducer");
	}

	$self->validate_url($$json{org}{website}, 'org.website', content_type => 'html', add_to_list => 'resources/website') || $error++;
	$self->validate_url($$json{org}{code_of_conduct}, 'org.code_of_conduct', content_type => 'html', add_to_list => 'resources/conduct') || $error++;
	$self->validate_url($$json{org}{ownership_disclosure}, 'org.ownership_disclosure', content_type => 'html', add_to_list => 'resources/ownership') || $error++;
	$self->validate_url($$json{org}{branding}{logo_256}, 'org.branding.logo_256', content_type => 'png_jpg', add_to_list => 'resources/social_logo_256') || $error++;
	$self->validate_url($$json{org}{branding}{logo_1024}, 'org.branding.logo_1024', content_type => 'png_jpg', add_to_list => 'resources/social_logo_1024') || $error++;
	$self->validate_url($$json{org}{branding}{logo_svg}, 'org.branding.logo_svg', content_type => 'svg', add_to_list => 'resources/social_logo_svg') || $error++;

	foreach my $key (sort keys %{$$json{org}{social}}) {
		my $value = $$json{org}{social}{$key};
		if ($value =~ m#https?://#) {
			$self->add_message('err', "social media references must be relative for field=<org.social.$key>");
		}
	}

	# ---------- check nodes

	my @nodes;
	eval {
		@nodes = @$json{nodes};
	};

	if (! @nodes) {
		$self->add_message('err', "no nodes configured");
		return undef;
	}

	my $node_number = 0;
	my $api_endpoint;
	my $peer_endpoint;
	foreach my $node (@{$$json{nodes}}) {
		my $found_something = 0;
		my $location = $self->validate_location($$node{location}, "node[$node_number].location");
		if ((defined $$node{api_endpoint}) && ($$node{api_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api($$node{api_endpoint}, "node[$node_number].api_endpoint", ssl => 'off', add_to_list => 'nodes/api_http', location => $location);
			if ($result) {
				if ($self->test_patreonous ($$node{api_endpoint}, "node[$node_number].api_endpoint")) {
					$api_endpoint++;
				} else {
					$error++;
				}
			} else {
				$error++;
			}
		}

		if ((defined $$node{ssl_endpoint}) && ($$node{ssl_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api($$node{ssl_endpoint}, "node[$node_number].ssl_endpoint", ssl => 'on', add_to_list => 'nodes/api_https', location => $location);
			if ($result) {
				if ($self->test_patreonous ($$node{ssl_endpoint}, "node[$node_number].ssl_endpoint")) {
					$api_endpoint++;
				} else {
					$error++;
				}
			} else {
				$error++;
			}
		}

		if ((defined $$node{p2p_endpoint}) && ($$node{p2p_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection($$node{p2p_endpoint}, "node[$node_number].p2p_endpoint", connection_type => 'p2p', add_to_list => 'nodes/p2p', location => $location)) {
				$peer_endpoint++;
			} else {
				$error++;
			}
		}

		if ((defined $$node{bnet_endpoint}) && ($$node{bnet_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection($$node{bnet_endpoint}, "node[$node_number].bnet_endpoint", connection_type => 'bnet', add_to_list => 'nodes/bnet', location => $location)) {
				$peer_endpoint++;
			} else {
				$error++;
			}
		}

		if (! $found_something) {
			$self->add_message('err', "no endpoints provided in field=<node[$node_number]> (useless section)");
		}
			
		$node_number++;
	}

	if (! $api_endpoint) {
		$self->add_message('err', "no API endpoints provided either api_endpoint or ssl_endpoint");
		$error++;
	}
	if (! $peer_endpoint) {
		$self->add_message('err', "no p2p or bnet endpoints provided");
		$error++;
	}

	# ---------- done
}

sub validate_string {
	my ($self, $string, $type) = @_;

	if (! $string) {
		$self->add_message('err', "no value given for field=<$type>");
		return undef;
	}

	return 1;
}

sub validate_url {
	my ($self, $url, $type, %options) = @_;

	#print ">> check url=[$url]\n";
	my $content_type = $options{content_type} || die "content_type not provided";
	my $ssl = $options{ssl} || 'either'; # either, on, off
	my $cors = $options{cors} || 'either'; #either, on, off, should
	my $url_ext = $options{url_ext} || '';

	if (! $url) {
		$self->add_message('err', "no url given for field=<$type>");
		return undef;
	}

	if ($self->{urls}{$url}) {
		$self->add_message('err', "duplicate url=<$url> for field=<$type>");		
		return undef;
	}
	$self->{urls}{$url} = 1;

	$url =~ s/#.*$//;

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message('err', "invalid url=<$url> for field=<$type>");
		return undef;
	}
	if ($url =~ m#^https?://.*//#) {
		$self->add_message('warn', "double slashes in url=<$url> for field=<$type>");
		$url =~ s#(^https?://.*)//#$1/#;
	}
	if ($url =~ m#^https?://localhost#) {
		$self->add_message('err', "localhost in url=<$url> for field=<$type>");
		return undef;
	}
	if ($url =~ m#^https?://127\.#) {
		$self->add_message('err', "localhost in url=<$url> for field=<$type>");
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
		die "$0: cannot determine host name";
	}

	#print ">> [$host_port]\n";
	my ($host, $port) = split (/:/, $host_port, 2);

	if ($protocol eq 'http' && $port && $port == 80) {
		$self->add_message('warn', "port 80 is not required in url=<$url> for field=<$type>");
	} elsif ($protocol eq 'https' && $port && $port == 443) {
		$self->add_message('warn', "port 443 ist not required in url=<$url> for field=<$type>");
	}
	if ($location && $location eq '/') {
		$self->add_message('warn', "trailing slash is not required in url=<$url> for field=<$type>");
	}

	if (defined $port) {
		if (! $self->validate_port($port, $type)) {
			return undef;
		}
	}
	if (! $self->validate_ip_dns($host, $type)) {
		return undef;
	}	

	if ($ssl eq 'either') {
		if ($url !~ m#^https://#) {
			$self->add_message('warn', "consider using https instead of http for url=<$url> for field=<$type>");
		}
	} elsif ($ssl eq 'on') {
		if ($url !~ m#^https://#) {
			$self->add_message('err', "need to specify https instead of http for url=<$url> for field=<$type>");
			return undef;
		}
	} elsif ($ssl eq 'off') {
		if ($url =~ m#^https://#) {
			$self->add_message('err', "need to specify http instead of https for url=<$url> for field=<$type>");
			return undef;
		}
	} else {
		die "unknown ssl option";
	}

	my $req = HTTP::Request->new('GET', $url . $url_ext);
	my $res = $self->ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_content_type = $res->content_type;

	if (! $res->is_success) {
		$self->add_message('err', "invalid url for field=<$type> for url=<$url> message=<$status_message>");
		return undef;
	}

	if ($options{api_checks}) {
		my $server_header = $res->header('Server');
		if ($server_header && $server_header =~ /cloudflare/) {
			$self->add_message('err', "cloudflare restricts some client use making this endpoint not appropriate for some use cases for url=<$url>");
			return undef;
		}

		my $cookie_header = $res->header('Set-Cookie');
		if ($cookie_header) {
			$self->add_message('err', "api nodes must not set cookies for url=<$url>");
			return undef;
		}
	}

	my $cors_header = $res->header('Access-Control-Allow-Origin');
	if ($cors eq 'either') {
		# do nothing
	} elsif ($cors eq 'should') {
		if (! $cors_header) {
			# error, but not fatal, but not ok either
			$self->add_message('err', "missing Access-Control-Allow-Origin header for field=<$type> for url=<$url>; see https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS");
			delete $options{add_to_list};
		}	
	} elsif ($cors eq 'on') {
		if (! $cors_header) {
			$self->add_message('err', "missing Access-Control-Allow-Origin header for field=<$type> for url=<$url>; see https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS");
			return undef;
		}	
	} elsif ($cors eq 'off') {
		if ($cors_header) {
			$self->add_message('err', "Access-Control-Allow-Origin header returned when should not be for field=<$type> for url=<$url>");
			return undef;
		}	
	} else {
		die "unknown cors option";
	}

	if (! $response_content_type) {
		$self->add_message('err', "did not receive content_type header for field=<$type> for url=<$url>");	
		return undef;
	} elsif ($content_type && $content_types{$content_type}) {
		my $found = 0;
		foreach my $x (@{$content_types{$content_type}}) {
			$found = 1 if ($x eq $response_content_type);
		}
		if (! $found) {
			$self->add_message('err', "received unexpected content_type=<$response_content_type> for field=<$type> for url=<$url>");
			return undef;
		}
	}

	my $content = $res->content;

	if ($response_url ne ($url . $url_ext)) {
		$self->add_message('warn', "url=<$url> for field=<$type> was redirected to url=<$response_url>");
		if ($ssl eq 'on') {
			if ($response_url !~ m#^https://#) {
				$self->add_message('err', "need to specify https instead of http for url=<$response_url> for field=<$type>");
				return undef;
			}
		} elsif ($ssl eq 'off') {
			if ($response_url =~ m#^https://#) {
				$self->add_message('err', "need to specify http instead of https for url=<$response_url> for field=<$type>");
				return undef;
			}
		}
	}

	my $json;
	if ($content_type eq 'json') {
		#printf ("%v02X", $content);
		if ($content =~ /^\xEF\xBB\xBF/) {
			$self->add_message('err', "remove BOM (byte order mark) from start of json for url=<$url>");
			$content =~ s/^\xEF\xBB\xBF//;
		}			
		eval {
			$json = from_json ($content, {utf8 => 1});
		};

		if ($@) {
			chomp ($@);
			$self->add_message('err', "invalid json for url=<$url> error=<$@>");
			#print $content;
			return undef;
		}
	} elsif ($content_type eq 'png_jpg') {
	} elsif ($content_type eq 'svg') {
	}

	$self->add_to_list($url, $type, result => $json, %options) if ($options{add_to_list});

	if ($json) {
		return $json;
	} else {
		return $res;
	}
}

sub validate_connection {
	my ($self, $peer, $type, %options) = @_;

	if ($self->{urls}{$peer}) {
		$self->add_message('err', "duplicate peer=<$peer> for field=<$type>");
		return undef;
	}
	$self->{urls}{$peer} = 1;

	if ($peer =~ m#^https?://#) {
		$self->add_message('err', "peer=<$peer> cannot begin with http(s) for field=<$type>");
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
	my $sh = new IO::Socket::INET (PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timemout => 5);
	if (! $sh) {
		$self->add_message('err', "cannot connect to peer=<$host:$port> for field=<$type>");
		return undef;
	}	
	close ($sh);

	$self->add_to_list($peer, $type, %options) if ($options{add_to_list});

	return 1;
}

sub validate_api {
	my ($self, $url, $type, %options) = @_;

	my $result = $self->validate_url($url, $type, url_ext => '/v1/chain/get_info', content_type => 'json', cors => 'on', api_checks => 'on', add_result_to_list => 'response', %options);
	my $errors;

	if (! $result) {
		return undef;
	}

	if (! $$result{chain_id}) {
		$self->add_message('err', "cannot find chain_id in response for url=<$url> for field=<$type>");
		$errors++;
	}

	if ($$result{chain_id} ne 'aca376f206b8fc25a6ed44dbdc66547c36c6c33e3a119ffbeaef943642f0e906') {
		$self->add_message('err', "invalid chain_id=<$$result{chain_id}> for url=<$url> for field=<$type>");
		$errors++;
	}


	if (! $$result{head_block_time}) {
		$self->add_message('err', "cannot find head_block_time in response for url=<$url> for field=<$type>");
		$errors++;
	}

	my $time = str2time($$result{head_block_time} . ' UTC');
	my $delta = abs(time - $time);
	
	if ($delta > 10) {
		my $val = Time::Seconds->new($delta);
		my $deltas = $val->pretty;
		#$self->add_message('err', "last block is off=<$$result{head_block_time}> delta=<$deltas> for url=<$url> for field=<$type>");
		$self->add_message('err', "last block is not up-to-date with timestamp=<$$result{head_block_time}> for url=<$url> for field=<$type>");
		$errors++;
	}

	if ($errors) {
		return undef;
	}
	return $result;
}

sub validate_port {
	my ($self, $port, $type) = @_;

	if (! defined $port) {
		$self->add_message('err', "port is not provided for field=<$type>");
		return undef;
	}
	if (! defined is_integer ($port)) {
		$self->add_message('err', "port=<$port> is not a valid integer for field=<$type>");
		return undef;
	}
	if (! is_between ($port, 1, 65535)) {
		$self->add_message('err', "port=<$port> is not a valid integer in range 1 to 65535 for field=<$type>");
		return undef;
	}

	return $port;
}

sub validate_ip_dns {
	my ($self, $host, $type) = @_;

	if (($host =~ /^[\d\.]+$/) || ($host =~ /^[\d\:]+$/)) {
		$self->add_message('warn', "better to use DNS names instead of IP address host=<$host> for field=<$type>");
		return $self->validate_ip($host, $type);
	} else {
		return $self->validate_dns($host, $type);
	}
}

sub validate_ip {
	my ($self, $ip, $type) = @_;

	if (! is_public_ip($ip)) {
		$self->add_message('err', "not a valid ip address=<$ip> for field=<$type>");
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
		$self->add_message('err', "cannot resolve DNS name=<$value> for field=<$type>");
		return undef;
	}
}

sub validate_location {
	my ($self, $location, $type) = @_;

	my $country = $self->validate_country($$location{country}, $type);
	my $name = $$location{name};
#	my $latitude = is_between ($$location{latitude}, -90, 90);
#	my $longitude = is_between ($$location{longitude}, -180, 180);  # not working?????
	my $latitude = is_numeric ($$location{latitude});
	my $longitude = is_numeric ($$location{longitude});

	if (! defined $name) {
		$self->add_message('err', "field=<$type> has no name");
		$name = undef;
	} elsif ($name eq $self->name) {
		$self->add_message('err', "field=<$type> has same name as producer, should be name of location");
		$name = undef;
	}

	if (! defined $latitude) {
		$self->add_message('err', "field=<$type> has no valid latitude");
	}
	if (! defined $longitude) {
		$self->add_message('err', "field=<$type> has no valid longitude");
	}
	if ((! defined $latitude) || (! defined $longitude)) {
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
		$self->add_message('err', "field=<$type> is not exactly 2 uppercase letters");
		return undef;
	} elsif (! code2country($country)) {
		$self->add_message('err', "field=<$type> is not a valid 2 letter country code");
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
		$self->add_message('err', "invalid patreonous filter for field=<$type> for url=<$url> message=<$status_message>; see https://github.com/EOSIO/patroneos/issues/36");
		return undef;
	}

	return 1;
}

sub add_message {
	my ($self, $kind, $message) = @_;

	push (@{$self->{messages}}, {kind => $kind, detail => $message});
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

	my $result;
	my $key;
	if ($options{add_result_to_list} && $options{result}) {
		$key = $options{add_result_to_list};
		$result = $options{result};
		$data{$key} = $result;
	}
	if ($options{location}) {
		$data{location} = $options{location};
	}

	push (@{$self->{results}{output}{$section}{$list}}, \%data);
}

1;

