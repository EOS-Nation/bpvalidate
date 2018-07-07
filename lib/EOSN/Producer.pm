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
use Net::DNS;
use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Carp qw(confess);
use Time::Seconds;

our %content_types;
$content_types{json} = ['application/json'];
$content_types{png_jpg} = ['image/png', 'image/jpeg'];
$content_types{svg} = ['image/svg+xml'];
$content_types{html} = ['text/html'];

our @bad_urls = ('https://google.com', 'https://www.yahoo.com');

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

	my $url = $self->{properties}{url};
	my $is_active = $self->{properties}{is_active};
	my $location = $self->{properties}{location};

	$self->add_message(kind => 'info', detail => 'voting rank', value => $self->{rank}, class => 'general');
	$self->{results}{rank} = $self->{rank};

	if (! $is_active) {
		$self->add_message(kind => 'skip', detail => 'producer is not active', class => 'regproducer');
		return undef;
	}

	#print ">> [$name][$key][$url][$votes]\n";

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message(kind => 'crit', detail => 'invalid configured URL', url => $url, class => 'regproducer');
		return undef;
	}

	$self->validate_country_n (country => $location, field => 'main location', class => 'regproducer');

	$self->validate_url(url => "$url", field => 'main web site', class => 'regproducer', content_type => 'html', cors => 'either', dupe => 'skip', add_to_list => 'resources/regproducer_url');

	my $json = $self->validate_url(url => "$url/bp.json", field => 'BP info JSON URL', class => 'org', content_type => 'json', cors => 'should', dupe => 'err', add_to_list => 'resources/bpjson');
	return undef if (! $json);

	$self->{results}{input} = $json;

	if (! ref $$json{org}) {
		$self->add_message(kind => 'err', detail => 'not a object', field => 'org', class => 'org');
	} else {
		$self->check_org_location;
		$self->check_org_misc;
		$self->check_org_branding;
		$self->check_org_social;
	}

	$self->check_nodes;
}

sub check_org_location {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{location}) {
		$self->add_message(kind => 'err', detail => 'not a object', field =>'org.location', class => 'org');
		return undef;
	}

	$self->validate_string(string => $$json{org}{location}{name}, field => 'org.location.name', class => 'org');
	$self->validate_location(location => $$json{org}{location}, field => 'org.location', class => 'org');
}

sub check_org_misc {
	my ($self) = @_;
	my $json = $self->{results}{input};
	my $name = $self->{properties}{owner};
	my $key = $self->{properties}{producer_key};

	$self->validate_string(string => $$json{org}{candidate_name}, field => 'org.candidate_name', class => 'org');
	$self->validate_email(string => $$json{org}{email}, field => 'org.email', class => 'org');
	$self->validate_string(string => $$json{producer_public_key}, field => 'producer_public_key', class => 'org');
	$self->validate_string(string => $$json{producer_account_name}, field => 'producer_account_name', class => 'org');

	if ($$json{producer_public_key} && $$json{producer_public_key} ne $key) {
		$self->add_message(kind => 'err', detail => 'no match between bp.json and regproducer', field => 'producer_public_key', class => 'org');
	}

	if ($$json{producer_account_name} && $$json{producer_account_name} ne $name) {
		$self->add_message(kind => 'crit', detail => 'no match between bp.json and regproducer', field => 'producer_account_name', class => 'org');
	}

	$self->validate_url(url => $$json{org}{website}, field => 'org.website', class => 'org', content_type => 'html', add_to_list => 'resources/website', dupe => 'warn');
	$self->validate_url(url => $$json{org}{code_of_conduct}, field => 'org.code_of_conduct', class => 'org', content_type => 'html', add_to_list => 'resources/conduct', dupe => 'warn');
	$self->validate_url(url => $$json{org}{ownership_disclosure}, field => 'org.ownership_disclosure', class => 'org', content_type => 'html', add_to_list => 'resources/ownership', dupe => 'warn');
}

sub check_org_branding {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{branding}) {
		$self->add_message(kind => 'err', detail => 'not a object', field =>'org.branding', class => 'org');
		return;
	}

	$self->validate_url(url => $$json{org}{branding}{logo_256}, field => 'org.branding.logo_256', class => 'org', content_type => 'png_jpg', add_to_list => 'resources/social_logo_256', dupe => 'warn');
	$self->validate_url(url => $$json{org}{branding}{logo_1024}, field => 'org.branding.logo_1024', class => 'org', content_type => 'png_jpg', add_to_list => 'resources/social_logo_1024', dupe => 'warn');
	$self->validate_url(url => $$json{org}{branding}{logo_svg}, field => 'org.branding.logo_svg', class => 'org', content_type => 'svg', add_to_list => 'resources/social_logo_svg', dupe => 'warn');
}

sub check_org_social {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{social}) {
		$self->add_message(kind => 'err', detail => 'not a object', field => 'org.social', class => 'org');
		return undef;
	}

	foreach my $key (sort keys %{$$json{org}{social}}) {
		my $value = $$json{org}{social}{$key};
		if ($value =~ m#https?://#) {
			$self->add_message(kind => 'err', detail => 'social media references must be relative', field => "org.social.$key", class => 'org');
		}
	}
}

sub check_nodes {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{nodes}) {
		$self->add_message(kind => 'err', detail => 'not a object', field => 'nodes', class => 'org');
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
		my $location = $self->validate_location(location => $$node{location}, field => "node[$node_number].location", class => 'org');
		my $node_type = $$node{node_type};

		# ---------- check type of node

		if ($$node{is_producer}) {
			$self->add_message(kind => 'warn', detail => "is_producer is deprecated use instead 'node_type' with one of the following values ['producer', 'full', 'query']", field => "node[$node_number].is_producer", class => 'endpoint');
			if ($$node{is_producer} && (! exists $$node{node_type})) {
				$node_type = 'producer';
				$$node{node_type} = 'producer'; # set this to avoid the error message below
			}
		}

		if ((! exists $$node{node_type}) || (! defined $$node{node_type})) {
			$self->add_message(kind => 'warn', detail => "node_type is not provided, set it to one of the following values ['producer', 'full', 'query']", field => "node[$node_number]", class => 'endpoint');
		} elsif (($$node{node_type} ne 'producer') && ($$node{node_type} ne 'full') && ($$node{node_type} ne 'query')) {
			$self->add_message(kind => 'err', detail => "node_type is not valid, set it to one of the following values ['producer', 'full', 'query']", field => "node[$node_number].node_type", class => 'endpoint');
		} else {
			$node_type = $$node{node_type};
		}

		# ---------- check endpoints

		if ((defined $$node{api_endpoint}) && ($$node{api_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api(url => $$node{api_endpoint}, field => "node[$node_number].api_endpoint", ssl => 'off', add_to_list => 'nodes/api_http', node_field => $node_type, location => $location);
			if ($result) {
				$api_endpoint++;
			}
		}

		if ((defined $$node{ssl_endpoint}) && ($$node{ssl_endpoint} ne '')) {
			$found_something++;
			my $result = $self->validate_api(url => $$node{ssl_endpoint}, field => "node[$node_number].ssl_endpoint", ssl => 'on', add_to_list => 'nodes/api_https', node_field => $node_type, location => $location);
			if ($result) {
				$api_endpoint++;
			}
		}

		if ((defined $$node{p2p_endpoint}) && ($$node{p2p_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection(peer => $$node{p2p_endpoint}, field => "node[$node_number].p2p_endpoint", connection_field => 'p2p', add_to_list => 'nodes/p2p', node_field => $node_type, location => $location)) {
				$peer_endpoint++;
			}
		}

		if ((defined $$node{bnet_endpoint}) && ($$node{bnet_endpoint} ne '')) {
			$found_something++;
			if ($self->validate_connection(peer => $$node{bnet_endpoint}, field => "node[$node_number].bnet_endpoint", connection_field => 'bnet', add_to_list => 'nodes/bnet', node_field => $node_type, location => $location)) {
				$peer_endpoint++;
			}
		}

		# ---------- check if something was found and compare to node type

		if (! defined $node_type) {
			# cannot check
		} elsif ($node_type eq 'producer') {
			if ($found_something) {
				$self->add_message(kind => 'warn', detail => 'endpoints provided (producer should be private)', field => "node[$node_number]", class => 'endpoint');
			}
		} else {
			if (! $found_something) {
				$self->add_message(kind => 'warn', detail => 'no endpoints provided (useless section)', field => "node[$node_number]", class => 'endpoint');
			}
		}
			
		$node_number++;
	}

	if (! $api_endpoint) {
		$self->add_message(kind => 'crit', detail => 'no API endpoints provided (that do not have errors noted) of either api_endpoint or ssl_endpoint', class => 'endpoint');
	}
	if (! $peer_endpoint) {
		$self->add_message(kind => 'crit', detail => 'no P2P or BNET endpoints provided (that do not have errors noted)', class => 'endpoint');
	}
}

sub validate_email {
	my ($self, %options) = @_;

	$self->validate_string (%options) || return;

	my $string = $options{string};
	my ($name, $host) = split (/@/, $string);

	$self->validate_mx($host, $options{field}, $options{class}) || return;
}

sub validate_string {
	my ($self, %options) = @_;

	my $string = $options{string};
	my $field = $options{field};
	my $class = $options{class};

	if ((! defined $string) || (length $string == 0)) {
		$self->add_message(kind => 'err', detail => 'no value given', field => $field, class => $class);
		return undef;
	}

	return 1;
}

sub validate_url {
	my ($self, %options) = @_;

	my $url = $options{url};
	my $field = $options{field} || confess "type not provided";
	my $class = $options{class} || confess "class not provided";
	my $content_type = $options{content_type} || confess "content_type not provided";
	my $ssl = $options{ssl} || 'either'; # either, on, off
	my $cors = $options{cors} || 'either'; #either, on, off, should
	my $url_ext = $options{url_ext} || '';
	my $non_standard_port = $options{non_standard_port}; # true/false
	my $dupe = $options{dupe} || confess "dupe checking not specified"; # err or warn or crit or skip
	my $timeout = $options{timeout} || 10;

	#print ">> check url=[GET $url$url_ext]\n";

	if (! $url) {
		$self->add_message(kind => 'err', detail => 'no URL given', field => $field, class => $class);
		return undef;
	}

	foreach my $test_url (@bad_urls) {
		if ($url =~ m#^$test_url#) {
			$self->add_message(kind => 'crit', detail => 'URL not allowed', field => $field, class => $class, url => $url);
			return undef;
		}
	}

	if ($dupe ne 'skip') {
		if ($self->{urls}{$url}) {
			$self->add_message(kind => $dupe, detail => 'duplicate URL', field => $field, class => $class, url => $url);
			return undef if ($dupe eq 'err');
		}
		$self->{urls}{$url} = 1;
	}

	$url =~ s/#.*$//;

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message(kind => 'err', detail => 'invalid URL', url => $url, field => $field, class => $class);
		return undef;
	}
	if ($url =~ m#^https?://.*//#) {
		$self->add_message(kind => 'warn', detail => 'double slashes in URL', url => $url, field => $field, class => $class);
		$url =~ s#(^https?://.*)//#$1/#;
	}
	if ($url =~ m#^https?://localhost#) {
		$self->add_message(kind => 'err', detail => 'localhost URL is invalid', url => $url, field => $field, class => $class);
		return undef;
	}
	if ($url =~ m#^https?://127\.#) {
		$self->add_message(kind => 'err', detail => 'localhost URL is invalid', url => $url, field => $field, class => $class);
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
		if (! $self->validate_port($port, $field, $class)) {
			return undef;
		}
	}

	if ($protocol eq 'http' && $port && $port == 80) {
		$self->add_message(kind => 'warn', detail => 'port is not required', url => $url, port => 80, field => $field, class => $class);
	} elsif ($protocol eq 'https' && $port && $port == 443) {
		$self->add_message(kind => 'warn', detail => 'port is not required', url => $url, port => 443, field => $field, class => $class);
	}
	if ($non_standard_port) {
		if ($protocol eq 'http' && $port && $port != 80) {
			$self->add_message(kind => 'info', detail => 'port is non-standard (not using 80) and may be unusable by some applications', url => $url, port => $port, field => $field, class => $class);
		} elsif ($protocol eq 'https' && $port && $port != 443) {
			$self->add_message(kind => 'info', detail => 'port is non-standard (not using 443) and may be unusable by some applications', url => $url, port => $port, field => $field, class => $class);
		}
	}
	if ($location && $location eq '/') {
		$self->add_message(kind => 'warn', detail => 'trailing slash is not required', url => $url, field => $field, class => $class);
	}

	if (! $self->validate_ip_dns($host, $field, $class)) {
		return undef;
	}	

	if ($ssl eq 'either') {
		if ($url !~ m#^https://#) {
			$self->add_message(kind => 'warn', detail => 'HTTPS is recommended instead of HTTP', url => $url, field => $field, class => $class, explanation => 'https://security.googleblog.com/2018/02/a-secure-web-is-here-to-stay.html');
		}
	} elsif ($ssl eq 'on') {
		if ($url !~ m#^https://#) {
			$self->add_message(kind => 'err', detail => 'need to specify HTTPS instead of HTTP', url => $url, field => $field, class => $class);
			return undef;
		}
	} elsif ($ssl eq 'off') {
		if ($url =~ m#^https://#) {
			$self->add_message(kind => 'err', detail => 'need to specify HTTP instead of HTTPS', url => $url, field => $field, class => $class);
			return undef;
		}
	} else {
		confess "unknown ssl option";
	}

	my $clock = time;

	my $req = HTTP::Request->new('GET', $url . $url_ext);
	$req->header('Origin', 'https://example.com');
	$self->ua->timeout($timeout * 2);
	my $res = $self->ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_content_type = $res->content_type;

	my $time = time - $clock;

	if (! $res->is_success) {
		$self->add_message(kind => 'crit', detail => 'invalid URL', value => $status_message, url => $url, field => $field, class => $class);
		return undef;
	}

	if ($time > $timeout) {
		$self->add_message(kind => 'err', detail => 'response took longer than expected', value => "$time s", target => "$timeout s", url => $url, field => $field, class => $class);
	}

	my @cors_headers = $res->header('Access-Control-Allow-Origin');
	if ($cors eq 'either') {
		# do nothing
	} elsif ($cors eq 'should') {
		# error, but not fatal, but not ok either
		if (! @cors_headers) {
			$self->add_message(kind => 'err', detail => 'missing Access-Control-Allow-Origin header', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		} elsif (@cors_headers > 1) {
			$self->add_message(kind => 'err', detail => 'multiple Access-Control-Allow-Origin headers=<@cors_headers>', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		} elsif ($cors_headers[0] ne '*') {
			$self->add_message(kind => 'err', detail => 'inappropriate Access-Control-Allow-Origin header=<@cors_headers>', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			delete $options{add_to_list};
		}	
	} elsif ($cors eq 'on') {
		if (! @cors_headers) {
			$self->add_message(kind => 'err', detail => 'missing Access-Control-Allow-Origin header', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		} elsif (@cors_headers > 1) {
			$self->add_message(kind => 'err', detail => 'multiple Access-Control-Allow-Origin headers=<@cors_headers>', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		} elsif ($cors_headers[0] ne '*') {
			$self->add_message(kind => 'err', detail => 'inappropriate Access-Control-Allow-Origin header=<@cors_headers>', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS');
			return undef;
		}	
	} elsif ($cors eq 'off') {
		if (@cors_headers) {
			$self->add_message(kind => 'err', detail => 'Access-Control-Allow-Origin header returned when should not be', url => $url, field => $field, class => $class);
			return undef;
		}	
	} else {
		confess "unknown cors option";
	}

	if (! $response_content_type) {
		$self->add_message(kind => 'err', detail => 'did not receive content_type header', url => $url, field => $field, class => $class);
		return undef;
	} elsif ($content_type && $content_types{$content_type}) {
		my $found = 0;
		foreach my $x (@{$content_types{$content_type}}) {
			$found = 1 if ($x eq $response_content_type);
		}
		if (! $found) {
			$self->add_message(kind => 'err', detail => 'received unexpected content_type', value => $response_content_type, url => $url, field => $field, class => $class);
			return undef;
		}
	}

	my $content = $res->content;

	if ($response_url ne ($url . $url_ext)) {
		$self->add_message(kind => 'info', detail => 'URL redirected', url => $url, field => $field, class => $class, response_url => '' .$response_url);
		if ($ssl eq 'on') {
			if ($response_url !~ m#^https://#) {
				$self->add_message(kind => 'err', detail => 'need to specify HTTPS instead of HTTP', url => $url, field => $field, class => $class, response_url => '' . $response_url);
				return undef;
			}
		} elsif ($ssl eq 'off') {
			if ($response_url =~ m#^https://#) {
				$self->add_message(kind => 'err', detail => 'need to specify HTTP instead of HTTPS', url => $url, field => $field, class => $class, response_url => '' . $response_url);
				return undef;
			}
		}
	}

	my $json;
	if ($content_type eq 'json') {
		#printf ("%v02X", $content);
		if ($content =~ /^\xEF\xBB\xBF/) {
			$self->add_message(kind => 'err', detail => 'remove BOM (byte order mark) from start of JSON', url => $url, field => $field, class => $class);
			$content =~ s/^\xEF\xBB\xBF//;
		}			
		eval {
			$json = from_json ($content, {utf8 => 1});
		};

		if ($@) {
			my $message = $@;
			chomp ($message);
			$message =~ s# at /usr/share/perl5/JSON.pm.*$##;
			$self->add_message(kind => 'err', detail => 'invalid JSON error', value => $message, url => $url, field => $field, class => $class);
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
		$info = $self->$function ($return, $res, %options);
		if (! $info) {
			return undef;
		}
	}

	$self->add_to_list(host => $url, info => $info, result => $json, %options) if ($options{add_to_list});

	return $return;
}

sub validate_connection {
	my ($self, %options) = @_;

	$options{class} = 'endpoint';

	my $peer = $options{peer};
	my $field = $options{field};
	my $class = $options{class};

	#print ">> peer=[$peer]\n";

	if ($self->{urls}{$peer}) {
		$self->add_message(kind => 'err', detail => 'duplicate peer', field => $field, class => $class, host => $peer);
		return undef;
	}
	$self->{urls}{$peer} = 1;

	if ($peer =~ m#^https?://#) {
		$self->add_message(kind => 'err', detail => 'peer cannot begin with http(s)://', field => $field, class => $class, host => $peer);
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

	$port = $self->validate_port ($port, $field, $class);
	if (! $port) {
		return undef;
	}

	my @hosts = $self->validate_ip_dns ($host, $field, $class);
	if (! @hosts) {
		return undef;
	}

	# need to be able to connect to at least one host

	my $success = 0;
	foreach my $host (@hosts) {
		#print ">> check connection to [$host]:[$port]\n";
		my $sh = new IO::Socket::INET (PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
		if ($sh) {
			$success++;
			close ($sh);
		} else {
			$self->add_message(kind => 'err', detail => 'cannot connect to peer', field => $field, class => $class, host => $host, port => $port);
		}
	}

	if (! $success) {
		return undef;
	}

	$self->add_to_list(host => $peer, %options) if ($options{add_to_list});
	return 1;
}

sub validate_api {
	my ($self, %options) = @_;

	my $url = $options{url};
	my $field = $options{field};

	return $self->validate_url(
		url => $url,
		field => $field,
		class => 'endpoint',
		url_ext => '/v1/chain/get_info',
		content_type => 'json',
		cors => 'on',
		non_standard_port => 1,
		extra_check => 'validate_api_extra_check',
		add_result_to_list => 'response',
		add_info_to_list => 'info',
		dupe => 'err',
		timeout => 2,
		%options
	);
}

sub validate_api_extra_check {
	my ($self, $result, $res, %options) = @_;

	my $url = $options{url};
	my $field = $options{field};
	my $class = $options{class};
	my $ssl = $options{ssl} || 'either'; # either, on, off
	my $url_ext = $options{url_ext} || '';

	my %info;
	my $errors;
	my $versions = $self->versions;

	my $server_header = $res->header('Server');
	if ($server_header && $server_header =~ /cloudflare/) {
		$self->add_message(kind => 'info', detail => 'cloudflare restricts some client use making this endpoint not appropriate for some use cases', url => $url, field => $field, class => $class, explanation => 'https://validate.eosnation.io/faq/#cloudflare');
		$errors++;
	}

	my $cookie_header = $res->header('Set-Cookie');
	if ($cookie_header) {
		$self->add_message(kind => 'err', detail => 'API nodes must not set cookies', url => $url, field => $field, class => $class);
		$errors++;
	}

	if ($ssl eq 'on') {
		# LWP doesn't seem to support HTTP2, so make an extra call
		my $check_http2 = `curl '$url$url_ext' --verbose --max-time 3 --stderr -`;
		if ($check_http2 =~ m#HTTP/2 200#) {
			$options{add_to_list} .= '2';
		} else {
			$self->add_message(kind => 'warn', detail => 'HTTPS API nodes would have better performance by using HTTP/2', url => $url, field => $field, class => $class, explanation => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages');
		}
	}

	if (! $$result{chain_id}) {
		$self->add_message(kind => 'crit', detail => 'cannot find chain_id in response', url => $url, field => $field, class => $class);
		$errors++;
	}

	if ($$result{chain_id} ne 'aca376f206b8fc25a6ed44dbdc66547c36c6c33e3a119ffbeaef943642f0e906') {
		$self->add_message(kind => 'crit', detail => 'invalid chain_id', value => $$result{chain_id}, url => $url, field => $field, class => $class);
		$errors++;
	}


	if (! $$result{head_block_time}) {
		$self->add_message(kind => 'crit', detail => 'cannot find head_block_time in response', url => $url, field => $field, class => $class);
		$errors++;
	}

	my $time = str2time($$result{head_block_time} . ' UTC');
	my $delta = abs(time - $time);
	
	if ($delta > 10) {
		my $val = Time::Seconds->new($delta);
		my $deltas = $val->pretty;
		#$self->add_message(kind => 'crit', detail => "last block is not up-to-date with timestamp=<$$result{head_block_time}> delta=<$deltas>", url => $url, field => $field, class => $class);
		$self->add_message(kind => 'crit', detail => 'last block is not up-to-date', value => $$result{head_block_time}, url => $url, field => $field, class => $class);
		$errors++;
	}

	if (! $$result{server_version}) {
		$self->add_message(kind => 'crit', detail => 'cannot find server_version in response', url => $url, field => $field, class => $class);
		$errors++;
	}

	if (! $$versions{$$result{server_version}}) {
		$self->add_message(kind => 'warn', detail => 'unknown server_version in response', value => $$result{server_version}, url => $url, field => $field, class => $class, explanation => 'https://validate.eosnation.io/faq/#versions');
	} else {
		my $name = $$versions{$$result{server_version}}{name};
		my $current = $$versions{$$result{server_version}}{current};
		$info{server_version} = $name;
		if (! $current) {
			$self->add_message(kind => 'warn', detail => 'server_version is out of date in response', value => $name, url => $url, field => $field, class => $class, explanation => 'https://validate.eosnation.io/faq/#versions');
		}
	}

	if (! $self->test_patreonous ($url, $field, $class)) {
		$errors++;
	}

	if ($errors) {
		return undef;
	}

	return \%info;
}

sub validate_port {
	my ($self, $port, $field, $class) = @_;

	if (! defined $port) {
		$self->add_message(kind => 'crit', detail => 'port is not provided', field => $field, class => $class);
		return undef;
	}
	if (! defined is_integer ($port)) {
		$self->add_message(kind => 'crit', detail => 'port is not a valid integer', field => $field, class => $class, port => $port);
		return undef;
	}
	if (! is_between ($port, 1, 65535)) {
		$self->add_message(kind => 'crit', detail => 'port is not a valid integer in range 1 to 65535', field => $field, class => $class, port => $port);
		return undef;
	}

	return $port;
}

sub validate_ip_dns {
	my ($self, $host, $field, $class) = @_;

	if (($host =~ /^[\d\.]+$/) || ($host =~ /^[\d\:]+$/)) {
		$self->add_message(kind => 'warn', detail => 'better to use DNS names instead of IP address', field => $field, class => $class, host => $host);
		return $self->validate_ip($host, $field, $class);
	} else {
		return $self->validate_dns([$host], $field, $class);
	}
}

sub validate_ip {
	my ($self, $ip, $field, $class) = @_;

	if (! is_public_ip($ip)) {
		$self->add_message(kind => 'crit', detail => 'not a valid ip address', field => $field, class => $class, ip => $ip);
		return undef;
	}

	return $ip;
}

sub validate_dns {
	my ($self, $addresses, $field, $class) = @_;

	# IPV6 checks are disabled for now
	# just allow these lintes when you want to test IPv6... right now IPv4 address is required everywhere

	my $res = new Net::DNS::Resolver;
	$res->tcp_timeout(10);
	my @results;

	foreach my $address (@$addresses) {
		my $reply6 = $res->query($address, "AAAA");

		if ($reply6) {
			foreach my $rr (grep {$_->type eq 'AAAA'} $reply6->answer) {
#IPV6				push (@results, $rr->address);
			}
		} else {
#IPV6			$self->add_message(kind => 'warn', detail => 'cannot resolve IPv6 DNS name', field => $field, class => 'ipv6', dns => $address);
		}

		my $reply4 = $res->query($address, "A");
		if ($reply4) {
			foreach my $rr (grep {$_->type eq 'A'} $reply4->answer) {
				push (@results, $rr->address);
			}
		} else {
#IPV6			$self->add_message(kind => 'warn', detail => 'cannot resolve IPv4 DNS name', field => $field, class => $class, dns => $address);
		}
	}

	if (! @results) {
		$self->add_message(kind => 'crit', detail => 'cannot resolve DNS name', field => $field, class => $class, dns => join (',', @$addresses));
	}

	return @results;
}

sub validate_mx {
	my ($self, $address, $field, $class) = @_;

	my $res = new Net::DNS::Resolver;
	$res->tcp_timeout(10);
	my @query;

	my $reply = $res->query($address, "MX");
	if ($reply) {
		foreach my $rr (grep {$_->type eq 'MX'} $reply->answer) {
			push (@query, $rr->exchange);
		}
	} else {
		$self->add_message(kind => 'crit', detail => 'cannot resolve MX name', field => $field, class => $class, dns => $address);
		return undef;
	}

	return $self->validate_dns(\@query, $field, $class);
}

sub validate_location {
	my ($self, %options) = @_;

	my $location = $options{location};
	my $field = $options{field};
	my $class = $options{class};

	my $country = $self->validate_country_a2(country => $$location{country}, field => $field, class => $class);
	my $name = $$location{name};
	my $latitude = is_numeric ($$location{latitude});
	my $longitude = is_numeric ($$location{longitude});

	if (! defined $name) {
		$self->add_message(kind => 'err', detail => 'no name', field => $field, class => $class);
		$name = undef;
	} elsif ($name eq $self->name) {
		$self->add_message(kind => 'err', detail => 'same name as producer, should be name of location', value => $name, field => $field, class => $class);
		$name = undef;
	}

	if (! defined $latitude) {
		$self->add_message(kind => 'err', detail => 'no latitude', field => $field, class => $class);
	}
	if (! defined $longitude) {
		$self->add_message(kind => 'err', detail => 'no longitude', field => $field, class => $class);
	}
	if ((! defined $latitude) || (! defined $longitude)) {
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $latitude) && ($latitude > 90 || $latitude < -90)) {
		$self->add_message(kind => 'err', detail => 'latitude out of range', value => $latitude, field => $field, class => $class);
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $longitude) && ($longitude > 180 || $longitude < -180)) {
		$self->add_message(kind => 'err', detail => 'longitude out of range', value => $longitude, field => $field, class => $class);
		$latitude = undef;
		$longitude = undef;
	}
	if (defined $latitude && defined $longitude && $latitude == 0 && $longitude == 0) {
		$self->add_message(kind => 'err', detail => 'latitude,longitude is 0,0', field => $field, class => $class);
		$latitude = undef;
		$longitude = undef;
	}

	my %return;
	$return{country} = $country if (defined $country);
	$return{name} = $name if (defined $name);
	$return{latitude} = $latitude if (defined $latitude);
	$return{longitude} = $longitude if (defined $longitude);

	if ($country && $name && $latitude && $longitude) {
		$self->add_message(kind => 'ok', detail => 'basic checks passed for location', value => "$country, $name", field => $field, class => $class);
	}

	return \%return;
}

sub validate_country_a2 {
	my ($self, %options) = @_;

	my $country = $options{country};
	my $field = $options{field};
	my $class = $options{class};

	$self->validate_string (string => $country, %options) || return;

	if ($country =~ /^[a-z]{2}$/) {
		$self->add_message(kind => 'warn', detail => 'country code should be uppercase', value => $country, suggested_value => uc($country), field => $field, class => $class);
		$country = uc ($country);
		my $country_validated = code2country($country);
		if (! $country_validated) {
			$self->add_message(kind => 'err', detail => 'not a valid 2 letter country code', value => $country, field => $field, class => $class);
			return undef;
		} else {
			$self->add_message(kind => 'ok', detail => 'valid country code', value => $country_validated, field => $field, class => $class);
		}
	} elsif ($country =~ /^[A-Z]{2}$/) {
		my $country_validated = code2country($country);
		if (! $country_validated) {
			$self->add_message(kind => 'err', detail => 'not a valid 2 letter country code', value => $country, field => $field, class => $class);
			return undef;
		} else {
			$self->add_message(kind => 'ok', detail => 'valid country code', value => $country_validated, field => $field, class => $class);
		}
	} else {
		my $code = country2code($country);
		if ($code) {
			$self->add_message(kind => 'err', detail => 'not a valid 2 letter country code using only uppercase letters', value => $country, suggested_value => uc($code), field => $field, class => $class);
		} else {
			$self->add_message(kind => 'err', detail => 'not a valid 2 letter country code using only uppercase letters', value => $country, field => $field, class => $class);
		}
		return undef;
	}

	return $country;
}

sub validate_country_n {
	my ($self, %options) = @_;

	my $country = $options{country};
	my $field = $options{field};
	my $class = $options{class};

	$self->validate_string (string => $country, %options) || return;

	if ($country =~ /^\d\d\d$/) {
		my $country_validated = code2country($country, LOCALE_CODE_NUMERIC);
		if (! $country_validated) {
			$self->add_message(kind => 'err', detail => 'not a valid 3 digit country code', value => $country, field => $field, class => $class);
			return undef;
		} else {
			$self->add_message(kind => 'ok', detail => 'valid country code', value => $country_validated, field => $field, class => $class);
		}
	} else {
		my $code = country2code($country, LOCALE_CODE_NUMERIC);
		if ($code) {
			$self->add_message(kind => 'err', detail => 'not a valid 3 digit country code', value => $country, suggested_value => uc($code), field => $field, class => $class);
		} else {
			$self->add_message(kind => 'err', detail => 'not a valid 3 digit country code', value => $country, field => $field, class => $class);
		}
		return undef;
	}

	return $country;
}

sub test_patreonous {
	my ($self, $base_url, $field, $class) = @_;
	my $url = "$base_url/v1/chain/get_table_rows";

	my $req = HTTP::Request->new('POST', $url, undef, '{"scope":"eosio", "code":"eosio", "table":"global", "json": true}');
	$self->ua->timeout(10);
	my $res = $self->ua->request($req);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;

	if (! $res->is_success) {
		$self->add_message(kind => 'crit', detail => 'invalid patreonous filter message', value => $status_message, field => $field, class => $class, url => $url, explanation => 'https://github.com/EOSIO/patroneos/issues/36');
		return undef;
	}

	return 1;
}

sub add_message {
	my ($self, %options) = @_;
	
	my $kind = $options{kind} || confess "missing kind";
	my $detail = $options{detail} || confess "missing detail";
	my $class = $options{class} || confess "missing class";

	push (@{$self->{messages}}, \%options);
}

sub add_to_list {
	my ($self, %options) = @_;

	my $host = $options{host} || confess "missing host";
	my $field = $options{field} || confess "missing type";
	my $class = $options{class} || confess "missing class";

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

	$self->add_message(kind => 'ok', detail => 'basic checks passed', resource => $options{add_to_list}, url => $host, field => $field, class => $class);
}

1;
