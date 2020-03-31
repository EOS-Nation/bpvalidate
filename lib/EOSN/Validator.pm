package EOSN::Validator;

use utf8;
use strict;
use JSON;
use Locale::Country;
use List::Util qw(maxstr);
use Data::Validate qw(is_integer is_numeric is_between);
use Data::Validate::IP qw(is_public_ip);
use IO::Socket;
use Net::DNS;
use Date::Format qw(time2str);
use Date::Parse qw(str2time);
use Carp qw(confess);
use Time::Seconds;
use Text::Diff;
use Time::HiRes qw(time);

our %content_types;
$content_types{json} = ['application/json'];
$content_types{png_jpg} = ['image/png', 'image/jpeg'];
$content_types{svg} = ['image/svg+xml'];
$content_types{html} = ['text/html'];

our %bad_urls;
$bad_urls{'https://google.com'} = {value => 'not a BP specific web site'};
$bad_urls{'https://www.yahoo.com'} = {value => 'not a BP specific web site'};
$bad_urls{'https://pbs.twimg.com'} = {value => 'does not load when tracking protection is enabled', see1 => 'https://developer.mozilla.org/en-US/Firefox/Privacy/Tracking_Protection'};

our %social;
$social{'medium'} = 'https://medium.com/@';
$social{'steemit'} = 'https://steemit.com/@';
$social{'twitter'} = 'https://twitter.com/';
$social{'youtube'} = 'https://www.youtube.com/';
$social{'facebook'} = 'https://www.facebook.com/';
$social{'github'} = 'https://github.com/';
#$social{'reddit'} = 'https://www.reddit.com/user/';
$social{'reddit'} = undef;
$social{'keybase'} = 'https://keybase.pub/';
$social{'telegram'} = 'https://t.me/';
$social{'wechat'} = undef;

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
	$self->summarize_messages;

	my $update_time = time2str("%C", time);

	$self->prefix_message(
		kind => 'info',
		detail => 'bp.json is re-validated approximately every 30 minutes; some URLs are checked less often',
		last_update_time => $update_time,
		class => 'general'
	);

	$self->{results}{meta}{generated_at} = $update_time;
	$self->{results}{meta}{elapsed_time} = $end_time - $start_time;

	return $self->{results};
}

sub summarize_messages {
	my ($self) = @_;

	my %sev;
	$sev{skip} = 6;
	$sev{crit} = 5;
	$sev{err} = 4;
	$sev{warn} = 3;
	$sev{info} = 2;
	$sev{ok} = 1;

	$self->{results}{messages} = $self->messages;

	my %results;

	foreach my $message (@{$self->{results}{messages}}) {
		my $code = $$message{kind};
		my $class = $$message{class};
		my $sev = $results{$class} || 'ok';
		if ($sev{$code} >= $sev{$sev}) {
			$results{$class} = $code;
		}
	}

	$self->{results}{message_summary} = \%results;
}

sub run_validate {
	my ($self) = @_;

	my $url = $self->{properties}{url};
	my $is_active = $self->{properties}{is_active};
	my $location = $self->{properties}{location};
	my $key = $self->{properties}{producer_key};
	my $chain = $self->{chain};
	my $bpjson_filename = $self->{chain_properties}{filename} || die "$0: filename is undefined in chains.csv";
	my $location_check = $self->{chain_properties}{location_check} || die "$0: location_check is undefined in chains.csv";
	my $chain_id = $self->{chain_properties}{chain_id} || die "$0: chain_id is undefined in chains.csv";

	$self->add_message(
		kind => 'info',
		detail => 'voting rank',
		value => $self->{rank},
		class => 'general'
	);
	$self->{results}{info}{rank} = $self->{rank};
	$self->{results}{info}{vote_percent} = $self->{vote_percent};

	if (! $is_active) {
		$self->add_message(
			kind => 'skip',
			detail => 'producer is not active',
			class => 'regproducer'
		);
		return undef;
	}

	if ($url !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_]*$#) {
		$self->add_message(
			kind => 'crit',
			detail => 'invalid configured URL',
			url => $url,
			class => 'regproducer'
		);
		return undef;
	}

	$self->test_regproducer_key (key => $key, class => 'regproducer', request_timeout => 10, cache_timeout => 300);

	if ($location_check eq 'country') {
		my $country = $self->validate_country_n (country => $location, class => 'regproducer');
		# country is not used for anything... see the one in the bpjson
		#if ($country) {
		#	$self->{results}{info}{country_number} = $country;
		#	my $countryx = code2country($country, LOCALE_CODE_NUMERIC);
		#	if ($countryx) {
		#		$self->{results}{info}{country_name} = $countryx;
		#		my $alpha = country_code2code($country, LOCALE_CODE_NUMERIC, LOCALE_CODE_ALPHA_2);
		#		$self->{results}{info}{country_alpha2} = $alpha;
		#	}
		#}
	} elsif ($location_check eq 'timezone') {
		if ($location !~ /^\d+/) {
			$self->add_message(
				kind => 'crit',
				detail => 'location is not a number (UTC offset)',
				value => $location,
				class => 'regproducer'
			);
		} elsif ($location < 0 || $location > 23) {
			$self->add_message(
				kind => 'crit',
				detail => 'location is not a number between 0 and 23 (UTC offset)',
				value => $location,
				class => 'regproducer'
			);
		} else {
			my $time_zone = '';
			if ($location == 0) {
				$time_zone = 'UTC+0';
			} elsif ($location >= 12) {
				$time_zone = 'UTC-' . (24 - $location);
			} else {
				$time_zone = 'UTC+' . $location;
			}
			$self->add_message(
				kind => 'ok',
				detail => 'location time zone',
				value => $time_zone,
				class => 'regproducer'
			);
			$self->{results}{info}{timezone} = $time_zone;
			$self->{results}{info}{timezone_value} = $location;
			#print ">>> TIME ZONE: $time_zone for location=<$location> url=<$url>\n";
		}	
	} elsif ($location_check eq 'timezone100') {
		if ($location !~ /^\d+/) {
			$self->add_message(
				kind => 'crit',
				detail => 'location is not a number (UTC offset)',
				value => $location,
				class => 'regproducer'
			);
		} elsif ($location < 0 || $location > 2399) {
			$self->add_message(
				kind => 'crit',
				detail => 'location is not a number between 0 and 2399 (UTC offset * 100)',
				value => $location,
				class => 'regproducer'
			);
		} else {
			my $time_zone = '';
			my $locationx = int($location / 100);
			if ($locationx == 0) {
				$time_zone = 'UTC+0';
			} elsif ($locationx >= 12) {
				$time_zone = 'UTC-' . (24 - $locationx);
			} else {
				$time_zone = 'UTC+' . $locationx;
			}
			$self->add_message(
				kind => 'ok',
				detail => 'location time zone',
				value => $time_zone,
				class => 'regproducer'
			);
			$self->{results}{info}{timezone} = $time_zone;
			$self->{results}{info}{timezone_value} = $location;
			#print ">>> TIME ZONE: $time_zone for location=<$location> url=<$url>\n";
		}
	} else {
		$self->add_message(
			kind => 'skip',
			detail => 'location check function needs to be fixed',
			class => 'regproducer'
		);
	}

	$self->validate_url(
		url => "$url",
		field => 'main web site',
		class => 'regproducer',
		content_type => 'html',
		cors_origin => 'either',
		cors_headers => 'either',
		dupe => 'skip',
		add_to_list => 'resources/regproducer_url',
		request_timeout => 10,
		cache_timeout => 300
	);

	my $xurl = $url;
	$xurl =~ s#/$##;

	# ----------- chains

	my $chains_json = $self->validate_url(
		url => "$xurl/chains.json",
		field => 'chains json',
		failure_code => 'err',
		class => 'chains',
		content_type => 'json',
		cors_origin => 'should',
		cors_headers => 'either',
		dupe => 'err',
		add_to_list => 'resources/chainjson',
		see1 => 'https://github.com/Telos-Foundation/telos/wiki/Telos:-bp.json',
		request_timeout => 10,
		cache_timeout => 300
	);
	if ($chains_json) {
		my $count = scalar (keys %{$$chains_json{chains}});
		if ($count) {
			$self->add_message(
				kind => 'ok',
				detail => 'chains found in chains.json',
				value => $count,
				class => 'chains'
			);
		} else {
			$self->add_message(
				kind => 'err',
				detail => 'no chains found in chains.json',
				class => 'chains'
			);
		}
		my $new_filename = $$chains_json{chains}{$chain_id};
		if ($new_filename) {
			$self->add_message(
				kind => 'ok',
				detail => 'using chain-specific bp.json',
				value => $new_filename,
				class => 'chains'
			);
			$new_filename =~ s#^/##;
			$bpjson_filename = $new_filename;
			#print ">>> CHAINS JSON: count=<$count> url=<$xurl/$new_filename>\n";
		} else {
			$self->add_message(
				kind => 'err',
				detail => 'could not find found chain specific bp.json',
				class => 'chains',
				see1 => 'https://github.com/Telos-Foundation/telos/wiki/Telos:-bp.json'
			);
		}
	} else {
		#print ">>> NO CHAINS JSON\n";
	}

	# ----------- bp.json

	my $json = $self->validate_url(
		url => "$xurl/$bpjson_filename",
		field => 'BP info JSON URL',
		class => 'org',
		content_type => 'json',
		cors_origin => 'should',
		cors_headers => 'either',
		dupe => 'err',
		add_to_list => 'resources/bpjson',
		request_timeout => 10,
		cache_timeout => 300
	);
	return undef if (! $json);

	$self->{results}{input} = $json;

	if (! ref $$json{org}) {
		$self->add_message(
			kind => 'err',
			detail => 'not a object',
			field => 'org',
			class => 'org'
		);
	} else {
		$self->check_org_misc;
		$self->check_org_location;
		$self->check_org_branding;
		$self->check_org_social;
	}

	$self->check_nodes;

	$self->check_onchainbpjson;
	$self->check_onchainblacklist;
}

sub check_onchainbpjson {
	my ($self) = @_;

	my $contract =  $self->{chain_properties}{test_bpjson_scope};
	my %message_options = (contract => $contract, class => 'bpjson');

	my $onchainbpjson_enabled = $self->{onchainbpjson_enabled};
	my $onchainbpjson_data = $self->{onchainbpjson_data};
	if (! $onchainbpjson_enabled) {
		#print "onchainbpjson not enabled\n";
		return;
	}
	if (! $onchainbpjson_data) {
		$self->add_message(
			kind => 'crit',
			detail => 'bp.json has not been provided on-chain',
			see1 => 'https://steemit.com/eos/@greymass/an-eos-smart-contract-for-block-producer-information',
			%message_options
		);
		return;
	}

	#print "bpjson: $onchainbpjson_data\n";

	my $chain_json = $self->get_json ($onchainbpjson_data, %message_options);
	if (! $chain_json) {
		return;
	}

	my $file_json = $self->{results}{input};

	my $chain_text = to_json($chain_json, {canonical => 1, pretty => 1});
	my $file_text = to_json($file_json, {canonical => 1, pretty => 1});

	if ($chain_text ne $file_text) {
		$self->add_message(
			kind => 'err',
			detail => 'bp.json on-chain does not match the one provided in regproducer URL',
			see2 => 'https://github.com/EOS-Nation/bpvalidate/blob/master/util/',
			see1 => 'https://steemit.com/eos/@greymass/an-eos-smart-contract-for-block-producer-information',
			diff => diff(\$chain_text, \$file_text),
			%message_options
		);
		return;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'bp.json has been provided on-chain and matches what is in the regproducer URL',
		%message_options
	);
}

sub check_onchainblacklist {
	my ($self) = @_;

	my %message_options = (contract => 'theblacklist', class => 'blacklist');

	my $onchainblacklist_enabled = $self->{onchainblacklist_enabled};
	my $onchainblacklist_data = $self->{onchainblacklist_data};
	if (! $onchainblacklist_enabled) {
		#print "onchainblacklist not enabled\n";
		return;
	}
	if (! $onchainblacklist_data) {
		$self->add_message(
			kind => 'crit',
			detail => 'blacklist has not been provided on-chain',
			see1 => 'https://github.com/bancorprotocol/eos-producer-heartbeat-plugin',
			%message_options
		);
		return;
	}

	#print "blacklist: $onchainblacklist_data\n";

	$self->{results}{output}{chain}{blacklist} = $onchainblacklist_data;

	$self->add_message(
		kind => 'ok',
		detail => 'blacklist has been provided on-chain',
		value => $onchainblacklist_data,
		%message_options
	);
}

sub check_org_location {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{location}) {
		$self->add_message(
			kind => 'err',
			detail => 'not a object',
			field =>'org.location',
			class => 'org'
		);
		return undef;
	}

	$self->validate_string(
		string => $$json{org}{location}{name},
		field => 'org.location.name',
		class => 'org'
	);
	my $results = $self->validate_location(
		location => $$json{org}{location},
		field => 'org.location',
		class => 'org'
	);

	if ($$results{country}) {
		my $country = $$results{country};
		my $country_name = code2country($country, LOCALE_CODE_ALPHA_2);
		if ($country_name) {
			#print ">>> country_name=<$country_name> country_abbreviation=<$country>\n";
			$self->{results}{info}{country_name} = $country_name;
			$self->{results}{info}{country_alpha2} = lc($country);
		}
	}
}

sub check_org_misc {
	my ($self) = @_;
	my $json = $self->{results}{input};
	my $name = $self->{properties}{owner};
	my $key = $self->{properties}{producer_key};

	$self->validate_string(
		string => $$json{org}{candidate_name},
		field => 'org.candidate_name',
		class => 'org'
	);
	$self->validate_email(
		string => $$json{org}{email},
		field => 'org.email',
		class => 'org'
	);
#	$self->validate_string(
#		string => $$json{producer_public_key},
#		field => 'producer_public_key',
#		class => 'org'
#	);
	$self->validate_string(
		string => $$json{producer_account_name},
		field => 'producer_account_name',
		class => 'org'
	);

	if ($$json{producer_account_name} && $$json{producer_account_name} ne $name) {
		$self->add_message(
			kind => 'crit',
			detail => 'no match between bp.json and regproducer',
			field => 'producer_account_name',
			class => 'org'
		);
	} else {
		if ($$json{org}{candidate_name}) {
			$self->{results}{info}{name} = $$json{org}{candidate_name};
		}
	}

	if ($$json{producer_public_key}) {
		$self->add_message(
			kind => 'info',
			detail => 'producer_public_key is not useful',
			see1 => 'https://github.com/eosrio/bp-info-standard/issues/7',
			field => 'producer_public_key',
			class => 'org'
		);
	}

# removed July, 2018: https://github.com/EOS-Nation/bpvalidate/issues/27
#	if ($$json{producer_public_key} && $$json{producer_public_key} ne $key) {
#		$self->add_message(
#			kind => 'err',
#			detail => 'no match between bp.json and regproducer',
#			field => 'producer_public_key',
#			class => 'org'
#		);
#	}

	$self->validate_url(
		url => $$json{org}{website},
		field => 'org.website',
		class => 'org',
		content_type => 'html',
		add_to_list => 'resources/website',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);
	$self->validate_url(
		url => $$json{org}{code_of_conduct},
		field => 'org.code_of_conduct',
		class => 'org',
		content_type => 'html',
		add_to_list => 'resources/conduct',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);
	$self->validate_url(
		url => $$json{org}{ownership_disclosure},
		field => 'org.ownership_disclosure',
		class => 'org',
		content_type => 'html',
		add_to_list => 'resources/ownership',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);

	return 1;
}

sub check_org_branding {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{branding}) {
		$self->add_message(
			kind => 'err',
			detail => 'not a object',
			field =>'org.branding',
			class => 'org'
		);
		return;
	}

	$self->validate_url(
		url => $$json{org}{branding}{logo_256},
		field => 'org.branding.logo_256',
		class => 'org',
		content_type => 'png_jpg',
		add_to_list => 'resources/social_logo_256',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);
	$self->validate_url(
		url => $$json{org}{branding}{logo_1024},
		field => 'org.branding.logo_1024',
		class => 'org',
		content_type => 'png_jpg',
		add_to_list => 'resources/social_logo_1024',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);
	$self->validate_url(
		url => $$json{org}{branding}{logo_svg},
		field => 'org.branding.logo_svg',
		class => 'org',
		content_type => 'svg',
		add_to_list => 'resources/social_logo_svg',
		dupe => 'warn',
		request_timeout => 10,
		cache_timeout => 7 * 24 * 3600,
		cache_fast_fail => 1
	);
}

sub check_org_social {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{org}{social}) {
		$self->add_message(
			kind => 'err',
			detail => 'not a object',
			field => 'org.social',
			class => 'org'
		);
		return undef;
	}

	my $valid = 0;
	foreach my $key (sort keys %social) {
		next if (! exists $$json{org}{social}{$key});
		next if ($$json{org}{social}{$key} eq '');
		my $value = $$json{org}{social}{$key};
		my $url_prefix = $social{$key};

		if ($value =~ m#^https?://#) {
			$self->add_message(
				kind => 'err',
				detail => 'social references must be relative',
				field => "org.social.$key",
				class => 'org'
			);
			next;
		}

		if ($value =~ /^@/) {
			$self->add_message(
				kind => 'err',
				detail => 'social references must not start with the at symbol',
				field => "org.social.$key",
				class => 'org'
			);
			next;
		}

		if ($url_prefix) {
			my $url = $url_prefix . $value;
			$url .= '/' if ($key eq 'keybase');
			if (! $self->validate_url(
				url => $url,
				field => "org.social.$key",
				failure_code => 'err',
				class => 'org',
				content_type => 'html',
				add_to_list => "social/$key",
				dupe => 'warn',
				request_timeout => 10,
				cache_timeout => 7 * 24 * 3600,
				cache_fast_fail => 1
			)) {
				next;
			}
		} else {
			$self->add_message(
				kind => 'ok',
				detail => 'valid social reference',
				value => $value,
				field => "org.social.$key",
				class => 'org'
			);
		}

		$valid++;
	}

	foreach my $key (keys %{$$json{org}{social}}) {
		next if (exists $social{$key});
		$self->add_message(
			kind => 'err',
			detail => 'unknown social reference',
			field => "org.social.$key",
			class => 'org'
		);
	}

	if ($valid < 4) {
		$self->add_message(
			kind => 'err',
			detail => 'should have at least 4 social references',
			field => "org.social",
			class => 'org'
		);
	}
}

sub check_nodes {
	my ($self) = @_;
	my $json = $self->{results}{input};

	if (! ref $$json{nodes}) {
		$self->add_message(
			kind => 'err',
			detail => 'not a object',
			field => 'nodes',
			class => 'org'
		);
		return undef;
	}	

	my @nodes;
	eval {
		@nodes = @{$$json{nodes}};
	};

	my $node_number = 0;
	my $total_valid_api_endpoint = 0;
	my $total_valid_ssl_endpoint = 0;
	my $total_valid_p2p_endpoint = 0;
	my $total_found_api_endpoint = 0;
	my $total_found_ssl_endpoint = 0;
	my $total_found_p2p_endpoint = 0;
	my $count_node_type_full = 0;
	my $count_node_type_seed = 0;
	my $count_node_type_producer = 0;

	foreach my $node (@nodes) {
		my $location = $self->validate_location(
			location => $$node{location},
			field => "node[$node_number].location",
			class => 'org'
		);
		my $node_type = $$node{node_type};
		my $valid_api_endpoint = 0;
		my $valid_ssl_endpoint = 0;
		my $valid_p2p_endpoint = 0;
		my $found_api_endpoint = 0;
		my $found_ssl_endpoint = 0;
		my $found_p2p_endpoint = 0;

		# ---------- check endpoints

		if ((defined $$node{api_endpoint}) && ($$node{api_endpoint} ne '')) {
			$found_api_endpoint++;
			my $result = $self->validate_basic_api(
				class => 'endpoint',
				api_url => $$node{api_endpoint},
				field => "node[$node_number].api_endpoint",
				ssl => 'off',
				add_to_list => 'nodes/api_http',
				node_type => $node_type,
				location => $location
			);
			if ($result) {
				$valid_api_endpoint++;
				my $result_history = $self->validate_history_api(
					class => 'history',
					api_url => $$node{api_endpoint},
					history_type => $$node{history_type},
					field => "node[$node_number].api_endpoint",
					ssl => 'off',
					add_to_list => 'nodes/history_http',
					node_type => $node_type,
					location => $location
				);
				my $result_hyperion = $self->validate_hyperion_api(
					class => 'hyperion',
					api_url => $$node{api_endpoint},
					history_type => $$node{history_type},
					field => "node[$node_number].api_endpoint",
					ssl => 'off',
					add_to_list => 'nodes/hyperion_http',
					node_type => $node_type,
					location => $location
				);
			}
		}

		if ((defined $$node{ssl_endpoint}) && ($$node{ssl_endpoint} ne '')) {
			$found_ssl_endpoint++;
			my $result = $self->validate_basic_api(
				class => 'endpoint',
				api_url => $$node{ssl_endpoint},
				field => "node[$node_number].ssl_endpoint",
				ssl => 'on',
				add_to_list => 'nodes/api_https',
				node_type => $node_type,
				location => $location
			);
			if ($result) {
				$valid_ssl_endpoint++;
				my $result_history = $self->validate_history_api(
					class => 'history',
					api_url => $$node{ssl_endpoint},
					history_type => $$node{history_type},
					field => "node[$node_number].ssl_endpoint",
					ssl => 'on',
					add_to_list => 'nodes/history_https',
					node_type => $node_type,
					location => $location
				);
				my $result_hyperion = $self->validate_hyperion_api(
					class => 'hyperion',
					api_url => $$node{ssl_endpoint},
					history_type => $$node{history_type},
					field => "node[$node_number].ssl_endpoint",
					ssl => 'on',
					add_to_list => 'nodes/hyperion_https',
					node_type => $node_type,
					location => $location
				);
			}
		}

		if ((defined $$node{p2p_endpoint}) && ($$node{p2p_endpoint} ne '')) {
			$found_p2p_endpoint++;
			if ($self->validate_connection(
					class => 'endpoint',
					peer => $$node{p2p_endpoint},
					field => "node[$node_number].p2p_endpoint",
					connection_type => 'p2p',
					add_to_list => 'nodes/p2p',
					node_type => $node_type,
					location => $location,
					dupe => 'info'
			)) {
				$valid_p2p_endpoint++;
			}
		}

		# ---------- check type of node

		if (exists $$node{is_producer}) {
			if ($$node{is_producer} && (! exists $$node{node_type})) {
				$self->add_message(
					kind => 'warn',
					detail => "is_producer is deprecated use instead 'node_type' with one of the following values ['producer', 'full', 'query', 'seed']",
					field => "node[$node_number].is_producer",
					class => 'endpoint'
				);
				$node_type = 'producer';
			} else {
				$self->add_message(
					kind => 'info',
					detail => "is_producer is deprecated and can be removed",
					field => "node[$node_number].is_producer",
					class => 'endpoint'
				);
			}
		}

		# subsequent nodes of the same type can be empty so as to add
		# new locations for the existing endpoints
		# https://github.com/EOS-Nation/bpvalidate/issues/29

		if (! $node_type) {
			$self->add_message(
				kind => 'warn',
				detail => "node_type is not provided, set it to one of the following values ['producer', 'full', 'query', 'seed']",
				field => "node[$node_number]",
				class => 'endpoint'
			);
		} elsif ($node_type eq 'producer') {
			$count_node_type_producer++;
			if ($found_api_endpoint || $found_ssl_endpoint || $found_p2p_endpoint) {
				$self->add_message(
					kind => 'warn',
					detail => 'endpoints provided (producer should be private)',
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
		} elsif ($node_type eq 'seed') {
			$count_node_type_seed++;
			if (! $valid_p2p_endpoint && $count_node_type_seed == 1) {
				$self->add_message(
					kind => 'warn',
					detail => 'no valid peer endpoints provided',
					node_type => $node_type,
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
			if ($valid_api_endpoint || $valid_ssl_endpoint) {
				$self->add_message(
					kind => 'warn',
					detail => 'extranious API endpoints provided',
					node_type => $node_type,
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
		} elsif ($node_type eq 'query') {
			$self->add_message(
				kind => 'err',
				detail => 'use node_type=query is deprecated; use node_type=full instead',
				see1 => 'https://github.com/eosrio/bp-info-standard/issues/21',
				class => 'endpoint'
			);
		} elsif ($node_type eq 'full') {
			$count_node_type_full++;
			if ($valid_p2p_endpoint) {
				$self->add_message(
					kind => 'warn',
					detail => 'extranious peer endpoints provided',
					see1 => 'https://github.com/eosrio/bp-info-standard/issues/21',
					node_type => $node_type,
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
			if (! $valid_api_endpoint && ! $valid_ssl_endpoint && $count_node_type_full == 1) {
				$self->add_message(
					kind => 'warn',
					detail => 'no valid API endpoints provided',
					node_type => $node_type,
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
		} else {
			$self->add_message(
				kind => 'err',
				detail => "node_type is not valid, set it to one of the following values ['producer', 'full', 'query', 'seed']",
				field => "node[$node_number].node_type",
				class => 'endpoint'
			);
			if (! $found_api_endpoint && ! $found_ssl_endpoint && ! $found_p2p_endpoint) {
				$self->add_message(
					kind => 'warn',
					detail => 'no valid endpoints provided (useless section)',
					field => "node[$node_number]",
					class => 'endpoint'
				);
			}
		}

		$total_valid_api_endpoint += $valid_api_endpoint;
		$total_valid_ssl_endpoint += $valid_ssl_endpoint;
		$total_valid_p2p_endpoint += $valid_p2p_endpoint;
		$total_found_api_endpoint += $found_api_endpoint;
		$total_found_ssl_endpoint += $found_ssl_endpoint;
		$total_found_p2p_endpoint += $found_p2p_endpoint;
		$node_number++;
	}

	if (! $count_node_type_full) {
		$self->add_message(
			kind => 'err',
			detail => 'no full nodes provided',
			see1 => 'https://github.com/eosrio/bp-info-standard/issues/21',
			class => 'endpoint'
		);
	} else {
		$self->add_message(
			kind => 'ok',
			detail => 'full node(s) provided',
			count => $count_node_type_full,
			class => 'endpoint'
		);
	}
	if (! $count_node_type_seed) {
		$self->add_message(
			kind => 'err',
			detail => 'no seed nodes provided',
			see1 => 'https://github.com/eosrio/bp-info-standard/issues/21',
			class => 'endpoint'
		);
	} else {
		$self->add_message(
			kind => 'ok',
			detail => 'seed node(s) provided',
			count => $count_node_type_seed,
			class => 'endpoint'
		);
	}
	if (! $count_node_type_producer) {
		$self->add_message(
			kind => 'err',
			detail => 'no producer nodes provided',
			see1 => 'https://github.com/eosrio/bp-info-standard/issues/21',
			class => 'endpoint'
		);
	} else {
		$self->add_message(
			kind => 'ok',
			detail => 'producer node(s) provided',
			count => $count_node_type_producer,
			class => 'endpoint'
		);
	}

	if (! $total_found_api_endpoint && ! $total_found_ssl_endpoint) {
		$self->add_message(
			kind => 'crit',
			detail => 'no HTTP or HTTPS API endpoints provided in any node',
			class => 'endpoint'
		);
	} elsif (! $total_valid_api_endpoint && ! $total_valid_ssl_endpoint) {
		$self->add_message(
			kind => 'crit',
			detail => 'no valid HTTP or HTTPS API endpoints provided in any node; see above messages',
			class => 'endpoint'
		);
	} elsif (! $total_valid_ssl_endpoint) {
		$self->add_message(
			kind => 'warn',
			detail => 'no valid HTTPS API endpoints provided in any node',
			class => 'endpoint'
		);
	} elsif (! $total_valid_api_endpoint) {
		# similar check is implemented on https://eosreport.franceos.fr/
		# $self->add_message(
		#	kind => 'warn',
		#	detail => 'no valid HTTP API endpoints provided in any node',
		#	class => 'endpoint'
		#);
	}

	if (! $total_found_p2p_endpoint) {
		$self->add_message(
			kind => 'crit',
			detail => 'no P2P endpoints provided in any node',
			class => 'endpoint'
		);
	} elsif (! $total_valid_p2p_endpoint) {
		$self->add_message(
			kind => 'crit',
			detail => 'no valid P2P endpoints provided in any node; see above messages',
			class => 'endpoint'
		);
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
		$self->add_message(
			kind => 'err',
			detail => 'no value given',
			field => $field,
			class => $class
		);
		return undef;
	}

	return 1;
}

sub validate_url {
	my ($self, %options) = @_;

	my $xurl = $options{url} || $options{api_url};
	my $field = $options{field} || confess "field not provided";
	my $class = $options{class} || confess "class not provided";
	my $content_type = $options{content_type} || confess "content_type not provided";
	my $ssl = $options{ssl} || 'either'; # either, on, off
	my $cors_origin = $options{cors_origin} || 'either'; #either, on, off, should
	my $cors_headers = $options{cors_headers} || 'either'; #either, on, off, should
	my $url_ext = $options{url_ext} || '';
	my $non_standard_port = $options{non_standard_port}; # true/false
	my $dupe = $options{dupe} || confess "dupe checking not specified"; # err or warn or crit or skip
	my $failure_code = $options{failure_code} || 'crit'; # any valid options for 'kind'

	#print ">> check url=[GET $xurl$url_ext]\n";

	if (! $xurl) {
		$self->add_message(
			kind => 'err',
			detail => 'no URL given',
			%options
		);
		return undef;
	}

	foreach my $test_url (keys %bad_urls) {
		my $details = $bad_urls{$test_url};
		if ($xurl =~ m#^$test_url#) {
			$self->add_message(
				kind => 'crit',
				detail => 'URL not allowed',
				%options,
				%$details
			);
			return undef;
		}
	}

	if ($dupe ne 'skip') {
		return undef if (! $self->check_duplicates ($xurl, 'duplicate URL', %options));
	}

	$xurl =~ s/#.*$//;

	if ($xurl !~ m#^https?://[a-z-0-9A-Z.-/]+[a-z-0-9A-Z.-_%]*$#) {
		$self->add_message(
			kind => 'err',
			detail => 'invalid URL',
			%options
		);
		return undef;
	}
	if ($xurl =~ m#^https?://.*//#) {
		$self->add_message(
			kind => 'warn',
			detail => 'double slashes in URL',
			%options
		);
		$xurl =~ s#(^https?://.*)//#$1/#;
	}
	if ($xurl =~ m#^https?://localhost#) {
		$self->add_message(
			kind => 'err',
			detail => 'localhost URL is invalid',
			%options
		);
		return undef;
	}
	if ($xurl =~ m#^https?://127\.#) {
		$self->add_message(
			kind => 'err',
			detail => 'localhost URL is invalid',
			%options
		);
		return undef;
	}

	my $host_port;
	my $protocol;
	my $location;
	if ($xurl =~ m#^(https?)://(.*?)(/.*)$#) {
		$protocol = $1;
		$host_port = $2;
		$location = $3;
	} elsif ($xurl =~ m#^(https?)://(.*)$#) {
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
		$self->add_message(
			kind => 'warn',
			detail => 'port is not required',
			port => 80,
			%options
		);
	} elsif ($protocol eq 'https' && $port && $port == 443) {
		$self->add_message(
			kind => 'warn',
			detail => 'port is not required',
			port => 443,
			%options
		);
	}
	if ($non_standard_port) {
		if ($protocol eq 'http' && $port && $port != 80) {
			$self->add_message(
				kind => 'info',
				detail => 'port is non-standard (not using 80) and may be unusable by some applications',
				port => $port,
				%options
			);
		} elsif ($protocol eq 'https' && $port && $port != 443) {
			$self->add_message(
				kind => 'info',
				detail => 'port is non-standard (not using 443) and may be unusable by some applications',
				port => $port,
				%options
			);
		}
	}
	if ($location && $location eq '/') {
		$self->add_message(
			kind => 'warn',
			detail => 'trailing slash is not required',
			%options
		);
	}

	if (! $self->validate_ip_dns($host, $field, $class)) {
		return undef;
	}	

	if ($ssl eq 'either') {
		if ($xurl !~ m#^https://#) {
			$self->add_message(
				kind => 'warn',
				detail => 'HTTPS is recommended instead of HTTP',
				see1 => 'https://security.googleblog.com/2018/02/a-secure-web-is-here-to-stay.html',
				%options
			);
		}
	} elsif ($ssl eq 'on') {
		if ($xurl !~ m#^https://#) {
			$self->add_message(
				kind => 'err',
				detail => 'need to specify HTTPS instead of HTTP',
				%options
			);
			return undef;
		}
	} elsif ($ssl eq 'off') {
		if ($xurl =~ m#^https://#) {
			$self->add_message(
				kind => 'err',
				detail => 'need to specify HTTP instead of HTTPS',
				%options
			);
			return undef;
		}
	} else {
		confess "unknown ssl option";
	}


	my $req = HTTP::Request->new('GET', $xurl . $url_ext);
	$req->header('Origin', 'https://example.com');
	$req->header("Referer", 'https://validate.eosnation.io');
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_content_type = $res->content_type;

	if (! $res->is_success) {
		$self->add_message(
			kind => $failure_code,
			detail => 'invalid URL',
			value => $status_message,
			%options
		);
		return undef;
	}

	my @cors_origin = $res->header('Access-Control-Allow-Origin');
	if ($cors_origin eq 'either') {
		# do nothing
	} elsif ($cors_origin eq 'should') {
		# error, but not fatal, but not ok either
		if (! @cors_origin) {
			$self->add_message(
				kind => 'err',
				detail => 'missing Access-Control-Allow-Origin header',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		} elsif (@cors_origin > 1) {
			$self->add_message(
				kind => 'err',
				detail => 'multiple Access-Control-Allow-Origin headers=<@cors_origin>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		} elsif ($cors_origin[0] ne '*') {
			$self->add_message(
				kind => 'err',
				detail => 'inappropriate Access-Control-Allow-Origin header=<@cors_origin>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		}
	} elsif ($cors_origin eq 'on') {
		if (! @cors_origin) {
			$self->add_message(
				kind => 'err',
				detail => 'missing Access-Control-Allow-Origin header',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		} elsif (@cors_origin > 1) {
			$self->add_message(
				kind => 'err',
				detail => 'multiple Access-Control-Allow-Origin headers=<@cors_origin>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		} elsif ($cors_origin[0] ne '*') {
			$self->add_message(
				kind => 'err',
				detail => 'inappropriate Access-Control-Allow-Origin header=<@cors_origin>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		}
	} elsif ($cors_origin eq 'off') {
		if (@cors_origin) {
			$self->add_message(
				kind => 'err',
				detail => 'Access-Control-Allow-Origin header returned when should not be',
				%options
			);
			return undef;
		}
	} else {
		confess "unknown cors option";
	}

	my @cors_headers = $res->header('Access-Control-Allow-Headers');
	if ($cors_headers eq 'either') {
		# do nothing
	} elsif ($cors_headers eq 'should') {
		# error, but not fatal, but not ok either
		if (! @cors_headers) {
			$self->add_message(
				kind => 'err',
				detail => 'missing Access-Control-Allow-Headers header',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		} elsif (@cors_headers > 1) {
			$self->add_message(
				kind => 'err',
				detail => 'multiple Access-Control-Allow-Headers headers=<@cors_headers>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		} elsif (($cors_headers[0] ne '*') && (($cors_headers[0] !~ /Content-Type/) || ($cors_headers[0] !~ /Origin/) || ($cors_headers[0] !~ /Accept/))) {
			$self->add_message(
				kind => 'err',
				detail => 'inappropriate Access-Control-Allow-Headers, need "*" or "Content-Type", "Origin" and "Accept" header=<@cors_headers>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			delete $options{add_to_list};
		}
	} elsif ($cors_headers eq 'on') {
		if (! @cors_headers) {
			$self->add_message(
				kind => 'err',
				detail => 'missing Access-Control-Allow-Headers header',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		} elsif (@cors_headers > 1) {
			$self->add_message(
				kind => 'err',
				detail => 'multiple Access-Control-Allow-Headers headers=<@cors_headers>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		} elsif (($cors_headers[0] ne '*') && (($cors_headers[0] !~ /Content-Type/) || ($cors_headers[0] !~ /Origin/) || ($cors_headers[0] !~ /Accept/))) {
			$self->add_message(
				kind => 'err',
				detail => 'inappropriate Access-Control-Allow-Headers, need "*" or "Content-Type", "Origin" and "Accept" header=<@cors_headers>',
				see2 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS',
				%options
			);
			return undef;
		}
	} elsif ($cors_headers eq 'off') {
		if (@cors_headers) {
			$self->add_message(
				kind => 'err',
				detail => 'Access-Control-Allow-Headers header returned when should not be',
				%options
			);
			return undef;
		}
	} else {
		confess "unknown cors option";
	}

	if (! $response_content_type) {
		$self->add_message(
			kind => 'err',
			detail => 'did not receive content_type header',
			%options
		);
		return undef;
	} elsif ($content_type && $content_types{$content_type}) {
		my $found = 0;
		foreach my $x (@{$content_types{$content_type}}) {
			$found = 1 if ($x eq $response_content_type);
		}
		if (! $found) {
			$self->add_message(
				kind => 'err',
				detail => 'received unexpected content_type',
				value => $response_content_type,
				%options
			);
			return undef;
		}
	}

	my $content = $res->content;

	if ($response_url ne ($xurl . $url_ext)) {
		$self->add_message(
			kind => 'info',
			detail => 'URL redirected',
			response_url => '' . $response_url,
			%options
		);
		if ($ssl eq 'on') {
			if ($response_url !~ m#^https://#) {
				$self->add_message(
					kind => 'err',
					detail => 'need to specify HTTPS instead of HTTP',
					response_url => '' . $response_url,
					%options
				);
				return undef;
			}
		} elsif ($ssl eq 'off') {
			if ($response_url =~ m#^https://#) {
				$self->add_message(
					kind => 'err',
					detail => 'need to specify HTTP instead of HTTPS',
					response_url => '' . $response_url,
					%options
				);
				return undef;
			}
		}
	}

	my $json;
	if ($content_type eq 'json') {
		#printf ("%v02X", $content);
		if ($content =~ /^\xEF\xBB\xBF/) {
			$self->add_message(
				kind => 'err',
				detail => 'remove BOM (byte order mark) from start of JSON',
				%options
			);
			$content =~ s/^\xEF\xBB\xBF//;
		}

		$json = $self->get_json ($content, %options) || return undef;

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
		$info = $self->$function ($return, $res, \%options);
		if (! $info) {
			return undef;
		}
	}

	$self->add_to_list(info => $info, result => $json, %options) if ($options{add_to_list});

	return $return;
}

sub validate_connection {
	my ($self, %options) = @_;

	my $peer = $options{peer};
	my $dupe = $options{dupe} || confess "dupe checking not specified"; # err or warn or crit or skip
	my $field = $options{field} || confess "field not provided";
	my $class = $options{class} || confess "class not provided";
	delete $options{peer};

	#print ">> peer=[$peer]\n";

	return undef if (! $self->check_duplicates ($peer, 'duplicate peer', host => $peer, dupe => $dupe, %options));

	if ($peer =~ m#^https?://#) {
		$self->add_message(
			kind => 'err',
			detail => 'peer cannot begin with http(s)://',
			host => $peer,
			%options
		);
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

	my $errors = 0;
	foreach my $xhost (@hosts) {
		$errors++ if (! $self->do_validate_connection ($xhost, $port, %options));
	}

	if ($errors) {
		return undef;
	}

	if ($connection_type eq 'p2p') {
		$self->do_validate_p2p ($host, $port, %options);
	} else {
		$self->add_to_list(host => $peer, %options) if ($options{add_to_list});
	}

	return 1;
}

sub do_validate_p2p {
	my ($self, $host, $port, %options) = @_;

	my $url = $self->{chain_properties}{url};
	my $content = `p2ptest -a $url -h $host -p $port -b 29`;

	my $result = $self->get_json ($content, %options);
	return undef if (! $result);

	if ($$result{status} ne 'success') {
		print ">> p2p error $host:$port => $$result{error_detail}\n";
		$self->add_message(
			kind => 'err',
			detail => $$result{error_detail},
			host => $host,
			port => $port,
			%options
		);

		return undef;
	}

	my $speed = sprintf ("%d", $$result{speed});
	my $ok_speed = 2;
	my $errors = 0;

	if ($speed < $ok_speed) {
		$self->add_message(
			kind => 'warn',
			detail => 'p2p block transmission speed too slow',
			value => $speed,
			threshold => $ok_speed,
			host => $host,
			port => $port,
			%options
		);

		$errors++;
	} else {
		$self->add_message(
			kind => 'ok',
			detail => 'p2p block transmission speed ok',
			value => $speed,
			threshold => $ok_speed,
			host => $host,
			port => $port,
			%options
		);
	}

	if ($errors) {
		return undef;
	}

	my $info = {speed => $speed};

	$self->add_to_list(
		add_info_to_list => 'info',
		info => $info,
		add_result_to_list => 'response',
		result => $result,
		host => $host,
		port => $port,
		%options
	) if ($options{add_to_list});

	return $result;
}

sub do_validate_connection {
	my ($self, $host, $port, %options) = @_;

	#print ">> check connection to [$host]:[$port]\n";
	my $sh = new IO::Socket::INET (PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
	if (! $sh) {
		$self->add_message(
			kind => 'err',
			detail => 'cannot connect to peer',
			host => $host,
			port => $port,
			%options
		);

		return undef;
	}

	my $buffer;
	my $data = recv ($sh, $buffer, 1, MSG_PEEK | MSG_DONTWAIT);
	if (! defined $data) {
		close ($sh);
		return 1;
	}

	$self->add_message(
		kind => 'err',
		detail => 'connection to peer dropped',
		host => $host,
		port => $port,
		%options
	);

	return undef;
}

sub validate_basic_api {
	my ($self, %options) = @_;

	my $api_url = $options{api_url};
	my $field = $options{field};
	my $class = $options{class} || confess "class not provided";

	return $self->validate_url(
		api_url => $api_url,
		field => $field,
		class => $class,
		url_ext => '/v1/chain/get_info',
		content_type => 'json',
		cors_origin => 'on',
		cors_headers => 'on',
		non_standard_port => 1,
		extra_check => 'validate_basic_api_extra_check',
		add_result_to_list => 'response',
		add_info_to_list => 'info',
		dupe => 'info',
		request_timeout => 2,
		cache_timeout => 300,
		%options
	);
}

sub validate_hyperion_api {
	my ($self, %options) = @_;

	my $api_url = $options{api_url};
	my $history_type = $options{history_type};
	my $field = $options{field};
	my $class = $options{class} || confess "class not provided";

#	if ($history_type && $history_type ne 'hyperion') {
#		return;
#	}

	return $self->validate_url(
		api_url => $api_url,
		field => $field,
		class => $class,
		url_ext => '/v1/chain/get_info',
		content_type => 'json',
		cors_origin => 'on',
		cors_headers => 'on',
		non_standard_port => 1,
		extra_check => 'validate_hyperion_api_extra_check',
		add_result_to_list => 'response',
		add_info_to_list => 'info',
		dupe => 'info',
		request_timeout => 2,
		cache_timeout => 300,
		%options
	);
}

sub validate_history_api {
	my ($self, %options) = @_;

	my $api_url = $options{api_url};
	my $history_type = $options{history_type};
	my $field = $options{field};
	my $class = $options{class} || confess "class not provided";

#	if ($history_type && $history_type !~ /^(traditional|mongo)$/) {
#		return;
#	}

	return $self->validate_url(
		api_url => $api_url,
		field => $field,
		class => $class,
		url_ext => '/v1/chain/get_info',
		content_type => 'json',
		cors_origin => 'on',
		cors_headers => 'on',
		non_standard_port => 1,
		extra_check => 'validate_history_api_extra_check',
		add_result_to_list => 'response',
		add_info_to_list => 'info',
		dupe => 'info',
		request_timeout => 2,
		cache_timeout => 300,
		%options
	);
}

sub validate_basic_api_extra_check {
	my ($self, $result, $res, $options) = @_;

	my $url = $$options{api_url};
	my $field = $$options{field};
	my $class = $$options{class};
	my $node_type = $$options{node_type};
	my $ssl = $$options{ssl} || 'either'; # either, on, off
	my $url_ext = $$options{url_ext} || '';

	my %info;
	my $errors;
	my $versions = $self->versions;

# cookies should not be used for session routing, so this check is not required
#	my $server_header = $res->header('Server');
#	if ($server_header && $server_header =~ /cloudflare/) {
#		$self->add_message(
#			kind => 'info',
#			detail => 'cloudflare restricts some client use making this endpoint not appropriate for some use cases',
#			url => $url,
#			field => $field,
#			class => $class,
#			node_type => $node_type,
#			see1 => 'https://validate.eosnation.io/faq/#cloudflare'
#		);
#		$errors++;
#	}
#
#	my $cookie_header = $res->header('Set-Cookie');
#	if ($cookie_header) {
#		$self->add_message(
#			kind => 'err',
#			detail => 'API nodes must not set cookies',
#			url => $url,
#			field => $field,
#			class => $class,
#			node_type => $node_type
#		);
#		$errors++;
#	}

	if ($ssl eq 'on') {
		# LWP doesn't seem to support HTTP2, so make an extra call
		my $check_http2 = `curl '$url$url_ext' --verbose --max-time 3 --stderr -`;
		if ($check_http2 =~ m#HTTP/2 200#) {
			$$options{add_to_list} .= '2';
		} else {
			$self->add_message(
				kind => 'warn',
				detail => 'HTTPS API nodes would have better performance by using HTTP/2',
				url => $url,
				field => $field,
				class => $class,
				node_type => $node_type,
				see1 => 'https://developer.mozilla.org/en-US/docs/Web/HTTP/Messages'
			);
		}
	}

	if (! $$result{chain_id}) {
		$self->add_message(
			kind => 'crit',
			detail => 'cannot find chain_id in response',
			url => $url,
			field => $field,
			class => $class,
			node_type => $node_type
		);
		$errors++;
	}

	my $chain_id = $self->{chain_properties}{chain_id} || die "$0: chain_id is undefined in chains.csv";

	if ($$result{chain_id} ne $chain_id) {
		$self->add_message(
			kind => 'crit',
			detail => 'invalid chain_id',
			value => $$result{chain_id},
			url => $url,
			field => $field,
			class => $class,
			node_type => $node_type
		);
		$errors++;
	}


	if (! $$result{head_block_time}) {
		$self->add_message(
			kind => 'crit',
			detail => 'cannot find head_block_time in response',
			url => $url,
			field => $field,
			class => $class,
			node_type => $node_type
		);
		$errors++;
	}

	my $time = str2time($$result{head_block_time} . ' UTC');
	my $delta = abs(time - $time);
	
	if ($delta > 10) {
		my $val = Time::Seconds->new($delta);
		my $deltas = $val->pretty;
		#$self->add_message(
		#	kind => 'crit',
		#	detail => "last block is not up-to-date with timestamp=<$$result{head_block_time}> delta=<$deltas>",
		#	url => $url,
		#	field => $field,
		#	class => $class,
		#	node_type => $node_type
		#);
		$self->add_message(
			kind => 'crit',
			detail => 'last block is not up-to-date',
			value => $$result{head_block_time},
			url => $url,
			field => $field,
			class => $class,
			node_type => $node_type
		);
		$errors++;
	}

	my $server_version = $$result{server_version_string};

	if (! $server_version) {
		$self->add_message(
			kind => 'crit',
			detail => 'cannot find server_version_string in response',
			url => $url,
			field => $field,
			class => $class,
			node_type => $node_type
		);
		$errors++;
	} else {
		$server_version = $self->version_cleanup ($server_version);

		if (! $$versions{$server_version}) {
			$self->add_message(
				kind => 'warn',
				detail => 'unknown server_version in response',
				value => $$result{server_version_string},
				url => $url,
				field => $field,
				class => $class,
				node_type => $node_type,
				see1 => 'https://validate.eosnation.io/faq/#versions'
			);
		} else {
			my $name = $$versions{$server_version}{name};
			my $current = $$versions{$server_version}{api_current};
			$info{server_version} = $name;
			if (! $current) {
				$self->add_message(
					kind => 'warn',
					detail => 'server_version is out of date in response',
					value => $name,
					url => $url,
					field => $field,
					class => $class,
					node_type => $node_type,
					see1 => 'https://validate.eosnation.io/faq/#versions'
				);
			} else {
				$self->add_message(
					kind => 'ok',
					detail => 'server_version is ok',
					value => $name,
					url => $url,
					field => $field,
					class => $class,
					node_type => $node_type
				);
			}
		}
	}

	if (! $self->test_block_one (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_patreonous (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_error_message (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_abi_serializer (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_system_symbol (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_producer_api (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_db_size_api (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_net_api (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}

	if ($errors) {
		return undef;
	}

	return \%info;
}

sub validate_hyperion_api_extra_check {
	my ($self, $result, $res, $options) = @_;

	my $url = $$options{api_url};
	my $field = $$options{field};
	my $class = $$options{class};
	my $node_type = $$options{node_type};
	my $ssl = $$options{ssl} || 'either'; # either, on, off
	my $url_ext = $$options{url_ext} || '';

	my %info;
	my $errors;
	my $versions = $self->versions;

	if (! $self->test_hyperion_transaction (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_hyperion_actions (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_hyperion_key_accounts (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}

	if ($info{history_type}) {
		my $new_value = 'history_' . $info{history_type} . '_';
		$$options{add_to_list} =~ s/history_/$new_value/;
	}

	if ($errors) {
		return undef;
	}

	return \%info;
}

sub validate_history_api_extra_check {
	my ($self, $result, $res, $options) = @_;

	my $url = $$options{api_url};
	my $field = $$options{field};
	my $class = $$options{class};
	my $node_type = $$options{node_type};
	my $ssl = $$options{ssl} || 'either'; # either, on, off
	my $url_ext = $$options{url_ext} || '';

	my %info;
	my $errors;
	my $versions = $self->versions;

	if (! $self->test_history_transaction (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_history_actions (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}
	if (! $self->test_history_key_accounts (api_url => $url, request_timeout => 10, cache_timeout => 300, field => $field, class => $class, node_type => $node_type, info => \%info)) {
		$errors++;
	}

	if ($info{history_type}) {
		my $new_value = 'history_' . $info{history_type} . '_';
		$$options{add_to_list} =~ s/history_/$new_value/;
	}

	if ($errors) {
		return undef;
	}

	return \%info;
}

sub validate_port {
	my ($self, $port, $field, $class) = @_;

	if (! defined $port) {
		$self->add_message(
			kind => 'crit',
			detail => 'port is not provided',
			field => $field,
			class => $class
		);
		return undef;
	}
	if (! defined is_integer ($port)) {
		$self->add_message(
			kind => 'crit',
			detail => 'port is not a valid integer',
			field => $field,
			class => $class,
			port => $port
		);
		return undef;
	}
	if (! is_between ($port, 1, 65535)) {
		$self->add_message(
			kind => 'crit',
			detail => 'port is not a valid integer in range 1 to 65535',
			field => $field,
			class => $class,
			port => $port
		);
		return undef;
	}

	return $port;
}

sub validate_ip_dns {
	my ($self, $host, $field, $class) = @_;

	if (($host =~ /^[\d\.]+$/) || ($host =~ /^[\d\:]+$/)) {
		$self->add_message(
			kind => 'warn',
			detail => 'better to use DNS names instead of IP address',
			field => $field,
			class => $class,
			host => $host
		);
		return $self->validate_ip($host, $field, $class);
	} else {
		return $self->validate_dns([$host], $field, $class);
	}
}

sub validate_ip {
	my ($self, $ip, $field, $class) = @_;

	if (! is_public_ip($ip)) {
		$self->add_message(
			kind => 'crit',
			detail => 'not a valid ip address',
			field => $field,
			class => $class,
			ip => $ip
		);
		return ();
	}

	return ($ip);
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
#IPV6			$self->add_message(
#				kind => 'warn',
#				detail => 'cannot resolve IPv6 DNS name',
#				field => $field,
#				class => 'ipv6',
#				dns => $address
#			);
		}

		my $reply4 = $res->query($address, "A");
		if ($reply4) {
			foreach my $rr (grep {$_->type eq 'A'} $reply4->answer) {
				push (@results, $rr->address);
			}
		} else {
#IPV6			$self->add_message(
#				kind => 'warn',
#				detail => 'cannot resolve IPv4 DNS name',
#				field => $field,
#				class => $class,
#				dns => $address
#			);
		}
	}

	if (! @results) {
		$self->add_message(
			kind => 'crit',
			detail => 'cannot resolve DNS name',
			field => $field,
			class => $class,
			dns => join (',', @$addresses)
		);
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
		$self->add_message(
			kind => 'crit',
			detail => 'cannot resolve MX name',
			field => $field,
			class => $class,
			dns => $address
		);
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
		$self->add_message(
			kind => 'err',
			detail => 'no name',
			field => $field,
			class => $class
		);
		$name = undef;
	} elsif ($name eq $self->name) {
		$self->add_message(
			kind => 'err',
			detail => 'same name as producer, should be name of location',
			value => $name,
			field => $field,
			class => $class
		);
		$name = undef;
	}

	if (! defined $latitude) {
		$self->add_message(
			kind => 'err',
			detail => 'no latitude',
			field => $field,
			class => $class
		);
	}
	if (! defined $longitude) {
		$self->add_message(
			kind => 'err',
			detail => 'no longitude',
			field => $field,
			class => $class
		);
	}
	if ((! defined $latitude) || (! defined $longitude)) {
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $latitude) && ($latitude > 90 || $latitude < -90)) {
		$self->add_message(
			kind => 'err',
			detail => 'latitude out of range',
			value => $latitude,
			field => $field,
			class => $class
		);
		$latitude = undef;
		$longitude = undef;
	}
	if ((defined $longitude) && ($longitude > 180 || $longitude < -180)) {
		$self->add_message(
			kind => 'err',
			detail => 'longitude out of range',
			value => $longitude,
			field => $field,
			class => $class
		);
		$latitude = undef;
		$longitude = undef;
	}
	if (defined $latitude && defined $longitude && $latitude == 0 && $longitude == 0) {
		$self->add_message(
			kind => 'err',
			detail => 'latitude,longitude is 0,0',
			field => $field,
			class => $class
		);
		$latitude = undef;
		$longitude = undef;
	}

	my %return;
	$return{country} = $country if (defined $country);
	$return{name} = $name if (defined $name);
	$return{latitude} = $latitude if (defined $latitude);
	$return{longitude} = $longitude if (defined $longitude);

	if ($country && $name && $latitude && $longitude) {
		$self->add_message(
			kind => 'ok',
			detail => 'basic checks passed for location',
			value => "$country, $name",
			field => $field,
			class => $class
		);
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
		$self->add_message(
			kind => 'warn',
			detail => 'country code should be uppercase',
			value => $country,
			suggested_value => uc($country),
			field => $field,
			class => $class
		);
		$country = uc ($country);
		my $country_validated = code2country($country);
		if (! $country_validated) {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 2 letter country code',
				value => $country,
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
			return undef;
		} else {
			$self->add_message(
				kind => 'ok',
				detail => 'valid country code',
				value => $country_validated,
				field => $field,
				class => $class
			);
		}
	} elsif ($country =~ /^[A-Z]{2}$/) {
		my $country_validated = code2country($country);
		if (! $country_validated) {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 2 letter country code',
				value => $country,
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
			return undef;
		} else {
			$self->add_message(
				kind => 'ok',
				detail => 'valid country code',
				value => $country_validated,
				field => $field,
				class => $class
			);
		}
	} else {
		my $code = country2code($country);
		if ($code) {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 2 letter country code using only uppercase letters',
				value => $country,
				suggested_value => uc($code),
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
		} else {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 2 letter country code using only uppercase letters',
				value => $country,
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
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

	if ($country =~ /^\d\d?$/) {
		$country = sprintf ("%03d", $country);
	}
	if ($country =~ /^\d\d\d$/) {
		my $country_validated = code2country($country, LOCALE_CODE_NUMERIC);
		if (! $country_validated) {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 3 digit country code',
				value => $options{country},
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
			return undef;
		} else {
			$self->add_message(
				kind => 'ok',
				detail => 'valid country code',
				value => $country_validated,
				field => $field,
				class => $class
			);
		}
	} else {
		my $code = country2code($country, LOCALE_CODE_NUMERIC);
		if ($code) {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 3 digit country code',
				value => $options{country},
				suggested_value => uc($code),
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
		} else {
			$self->add_message(
				kind => 'err',
				detail => 'not a valid 3 digit country code',
				value => $options{country},
				field => $field,
				class => $class,
				see1 => 'http://www.nationsonline.org/oneworld/country_code_list.htm'
			);
		}
		return undef;
	}

	return $country;
}

# --------------------------------------------------------------------------
# API Test Methods

sub test_block_one {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/chain/get_block';
	$options{post_data} = '{"block_num_or_id": "1", "json": true}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'invalid block one',
			value => $status_message,
			response_host => $response_host,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'block one test passed',
		%options
		);

	return 1;
}

sub test_patreonous {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/chain/get_table_rows';
	$options{post_data} = '{"scope":"eosio", "code":"eosio", "table":"global", "json": true}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'invalid patreonous filter message',
			value => $status_message,
			response_host => $response_host,
			see1 => 'https://github.com/EOSIO/patroneos/issues/36',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'patreonous filter test passed',
		%options
	);

	return 1;
}

sub test_error_message {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/chain/validate_error_message';
	$options{post_data} = '{"json": true}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	my $json = $self->get_json ($content, %options) || return undef;

	$self->check_response_errors (response => $res, %options);

	if ((ref $$json{error}{details} ne 'ARRAY') || (scalar (@{$$json{error}{details}}) == 0)) {
		$self->add_message(
			kind => 'err',
			response_host => $response_host,
			detail => 'detailed error messages not returned',
			explanation => 'edit config.ini to set verbose-http-errors = true',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'verbose errors test passed',
		%options
	);

	return 1;
}

sub test_abi_serializer {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/chain/get_block';

	my $big_block = $self->{chain_properties}{test_big_block};
	my $number_of_transactions = $self->{chain_properties}{big_block_transactions};

	if (! $big_block || ! $number_of_transactions) {
		warn "Cannot run test_abi_serializer because big_block or number_of_transactions is undefined in chains.csv; test disabled\n";
		return 1;
	}

	$options{post_data} = '{"json": true, "block_num_or_id": ' . $big_block . '}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'err',
			detail => 'error retriving large block',
			value => $status_message,
			response_host => $response_host,
			explanation => 'edit config.ini to set abi-serializer-max-time-ms = 2000 (or higher)',
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;

	my $transactions = $$json{transactions};
	my $transaction_count = @$transactions;

	if ($transaction_count != $number_of_transactions) {
		$self->add_message(
			kind => 'err',
			detail => 'large block does not contain correct amount of transactions',
			suggested_value => $number_of_transactions,
			value => $transaction_count,
			response_host => $response_host,
			explanation => 'edit config.ini to set abi-serializer-max-time-ms = 2000 (or higher)',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'abi serializer test passed',
		%options
	);

	return 1;
}

sub test_hyperion_transaction {
	my ($self, %options) = @_;

	my $base_url = $options{api_url};
	my $transaction = $self->{chain_properties}{test_transaction} || die "$0: test_transaction is undefined in chains.csv\n";

	$options{api_url} = $base_url . '/v2/history/get_transaction?id=' . $transaction;
	my $req = HTTP::Request->new('GET', $options{api_url});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving transaction history',
			value => $status_message,
			explanation => 'check hyperion configuration',
			response_host => $response_host,
			see1 => 'https://t.me/EOSHyperion',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_transaction hyperion test passed',
		%options
	);

	return 1;
}

sub test_hyperion_actions {
	my ($self, %options) = @_;

	$options{api_url} .= '/v2/history/get_actions?limit=1';

	my $req = HTTP::Request->new('GET', $options{api_url});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving actions history',
			value => $status_message,
			response_host => $response_host,
			explanation => 'check hyperion configuration',
			see1 => 'https://t.me/EOSHyperion',
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;
	if (! scalar (@{$$json{actions}})) {
		$self->add_message(
			kind => 'err',
			detail => 'invalid JSON response',
			response_host => $response_host,
			%options
		);
		return undef;
	}

	my $block_time = $$json{actions}[0]{'@timestamp'};
	my $time = str2time($block_time . ' UTC');
	my $delta = abs(time - $time);
	if ($delta > 300) {
		$self->add_message(
			kind => 'err',
			detail => 'hyperion not up-to-date: last action is more than 5 minutes in the past',
			value => $block_time,
			response_host => $response_host,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_actions hyperion test passed',
		%options
	);

	return 1;
}

sub test_hyperion_key_accounts {
	my ($self, %options) = @_;

	my $public_key = $self->{chain_properties}{test_public_key} || die "$0: test_public_key is undefined in chains.csv";
	$options{api_url} .= '/v2/state/get_key_accounts';
	$options{post_data} = '{"public_key": "' . $public_key . '"}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving key_accounts history',
			value => $status_message,
			response_host => $response_host,
			explanation => 'check hyperion configuration',
			see1 => 'https://t.me/EOSHyperion',
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;

	if (! scalar (@{$$json{account_names}})) {
		$self->add_message(
			kind => 'err',
			detail => 'invalid JSON response',
			response_host => $response_host,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_key_accounts hyperion test passed',
		%options
	);

	return 1;
}

sub test_history_transaction {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/history/get_transaction';
	my $transaction = $self->{chain_properties}{test_transaction} || die "$0: test_transaction is undefined in chains.csv\n";

	$options{post_data} = '{"json": true, "id": "' . $transaction . '"}';
	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving transaction history',
			value => $status_message,
			explanation => 'edit config.ini to turn on history and replay all blocks',
			response_host => $response_host,
			see1 => 'http://t.me/eosfullnodes',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_transaction history test passed',
		%options
	);

	return 1;
}

sub test_history_actions {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/history/get_actions';
	$options{post_data} = '{"json": true, "pos":-1, "offset":-120, "account_name": "eosio.token"}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving actions history',
			value => $status_message,
			response_host => $response_host,
			explanation => 'edit config.ini to turn on history and replay all blocks',
			see1 => 'http://t.me/eosfullnodes',
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;
	if (! scalar (@{$$json{actions}})) {
		$self->add_message(
			kind => 'err',
			detail => 'no actions included in the response',
			response_host => $response_host,
			%options
		);
		return undef;
	}

	my $last_irreversible_block = $$json{last_irreversible_block};
	my $history_type = undef;
	if ($last_irreversible_block) {
		$self->add_message(
			kind => 'ok',
			response_host => $response_host,
			detail => 'detect traditional history node',
			%options
		);
		$history_type = 'traditional';
	} else {
		$self->add_message(
			kind => 'ok',
			response_host => $response_host,
			detail => 'detect mongo history node',
			%options
		);
		$history_type = 'mongo';
	}
	$options{info}{history_type} = $history_type;

	my @actions = @{$$json{actions}};
	my $block_time = '2000-01-01';
	foreach my $action (@actions) {
		if (! defined $$action{block_time}) {
			warn "$0: action block time not defined";
			next;
		}
		$block_time = maxstr ($$action{block_time}, $block_time);
	}

	my $time = str2time($block_time . ' UTC');
	my $delta = abs(time - $time);
	if ($delta > 3600 * 2) {
		$self->add_message(
			kind => 'err',
			detail => 'history not up-to-date: eosio.ram action is more than 2 hours in the past',
			value => $block_time,
			response_host => $response_host,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_actions history test passed',
		%options
	);

	return 1;
}

sub test_history_key_accounts {
	my ($self, %options) = @_;

	my $public_key = $self->{chain_properties}{test_public_key} || die "$0: test_public_key is undefined in chains.csv";
	$options{api_url} .= '/v1/history/get_key_accounts';
	$options{post_data} = '{"json": true, "public_key": "' . $public_key . '"}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'crit',
			detail => 'error retriving key_accounts history',
			value => $status_message,
			response_host => $response_host,
			explanation => 'edit config.ini to turn on history and replay all blocks',
			see1 => 'http://t.me/eosfullnodes',
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;
	if (ref $json eq 'ARRAY') {
		$self->add_message(
			kind => 'err',
			detail => 'invalid JSON response (array)',
			response_host => $response_host,
			%options
		);
		return undef;
	}
	if ((! $$json{account_names}) || (! scalar (@{$$json{account_names}}))) {
		$self->add_message(
			kind => 'err',
			detail => 'invalid JSON response',
			response_host => $response_host,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'get_key_accounts history test passed',
		%options
	);

	return 1;
}

sub test_system_symbol {
	my ($self, %options) = @_;

	my $core_symbol = $self->{chain_properties}{core_symbol} || die "$0: core_symbol is undefined in chains.csv";
	my $test_account = $self->{chain_properties}{test_account} || die "$0: test_account is undefined in chains.csv";
	$options{api_url} .= '/v1/chain/get_currency_balance';
	$options{post_data} = '{"json": true, "account": "' . $test_account . '", "code":"eosio.token", "symbol": "' . $core_symbol . '"}';

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;

	$self->check_response_errors (response => $res, %options);

	if (! $res->is_success) {
		$self->add_message(
			kind => 'err',
			detail => 'error retriving symbol',
			value => $status_message,
			response_host => $response_host,
			%options
		);
		return undef;
	}

	my $json = $self->get_json ($content, %options) || return undef;
	if (! scalar (@$json)) {
		$self->add_message(
			kind => 'err',
			detail => 'code compiled with incorrect symbol',
			response_host => $response_host,
			%options
		);
		return undef;
	}
	$self->add_message(
		kind => 'ok',
		detail => 'basic symbol test passed',
		%options
	);

	return 1;
}

sub test_net_api {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/net/connections';

	my $req = HTTP::Request->new('GET', $options{api_url}, undef);
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;
        my $response_content_type = $res->content_type;

	$self->check_response_errors (response => $res, %options);

	if (($res->is_success) && ($response_url eq $options{api_url}))  {
		$self->add_message(
			kind => 'err',
			detail => 'net api is enabled',
			value => $status_message,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'net api disabled',
		%options
	);

	return 1;
}

sub test_producer_api {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/producer/get_integrity_hash';

	my $req = HTTP::Request->new('GET', $options{api_url}, undef);
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;
        my $response_content_type = $res->content_type;

	$self->check_response_errors (response => $res, %options);

	if (($res->is_success) && ($response_url eq $options{api_url}))  {
		$self->add_message(
			kind => 'err',
			detail => 'producer api is enabled',
			value => $status_message,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'producer api disabled',
		%options
	);

	return 1;
}

sub test_db_size_api {
	my ($self, %options) = @_;

	$options{api_url} .= '/v1/db_size/get';

	my $req = HTTP::Request->new('GET', $options{api_url}, undef);
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $response_host = $res->header('host');
	my $content = $res->content;
        my $response_content_type = $res->content_type;

	$self->check_response_errors (response => $res, %options);

	if (($res->is_success) && ($response_url eq $options{api_url}))  {
		$self->add_message(
			kind => 'err',
			detail => 'db_size api is enabled',
			value => $status_message,
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'db_size api disabled',
		%options
	);

	return 1;
}

sub test_regproducer_key {
	my ($self, %options) = @_;

	my $key = $options{key};
	$options{api_url} = $self->{chain_properties}{key_accounts_url};
	$options{post_data} = '{"json": true, "public_key": "' . $key . '"}';

	if (! $options{api_url}) {
		warn "Cannot run test_regproducer_key because key_accounts_url is undefined in chains.csv; test disabled\n";
		return 1;
	}

	my $req = HTTP::Request->new('POST', $options{api_url}, ['Content-Type' => 'application/json'], $options{post_data});
	my $res = $self->run_request ($req, \%options);
	my $status_code = $res->code;
	my $status_message = $res->status_line;
	my $response_url = $res->request->uri;
	my $content = $res->content;

	if (! $res->is_success) {
		# API endpoint is unavilable, so we can't run this test.  Assume ok
		warn "Cannot run test_regproducer_key due to endpoint error url=<$options{api_url}> status=<$status_code $status_message> data=<$options{post_data}>; remainder of test disabled\n";
		return 1;
	}

	my $json = $self->get_json ($content, %options) || return 1;  #skip if down

	if ((ref $$json{account_names} ne 'ARRAY') || (scalar @{$$json{account_names}} != 0)) {
		$self->add_message(
			kind => 'err',
			detail => 'regproducer key is assigned to an account; better to use a dedicated signing key',
			see1 => 'https://steemit.com/eos/@eostribe/eos-bp-guide-on-how-to-setup-a-block-signing-key',
			%options
		);
		return undef;
	}

	$self->add_message(
		kind => 'ok',
		detail => 'regproducer signing key test passed',
		%options
	);

	return 1;
}

# --------------------------------------------------------------------------
# Helper Methods

sub prefix_message {
	my ($self, %options) = @_;

	my $kind = $options{kind} || confess "missing kind";
	my $detail = $options{detail} || confess "missing detail";
	my $class = $options{class} || confess "missing class";

	unshift (@{$self->{messages}}, \%options);
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

	my $host = $options{host} || $options{url} || $options{api_url} || confess "missing host";
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
	if ($host && $options{port}) {
		$data{address} = "$host:$options{port}";
	} else {
		$data{address} = $host;
	}

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

	$self->add_message(
		kind => 'ok',
		detail => 'basic checks passed',
		resource => $options{add_to_list},
		%options
	);
}

sub get_json {
	my ($self, $content, %options) = @_;

	my $json;

	eval {
		$json = from_json ($content, {utf8 => 1});
	};

	if ($@) {
		my $message = $@;
		chomp ($message);
		$message =~ s# at /usr/share/perl5/JSON.pm.*$##;
		$self->add_message(
			kind => 'crit',
			detail => 'invalid JSON error',
			value => $message,
			%options
		);
		#print $content;
		return undef;
	}

	return $json;
}

sub check_duplicates {
	my ($self, $url, $message, %options) = @_;

	my $class = $options{class} || confess "class not provided";
	my $dupe = $options{dupe} || confess "dupe checking not specified"; # err or warn or crit or skip

	if ($self->{urls}{$class}{$url}) {
		$self->add_message(
			kind => $dupe,
			detail => 'duplicate URL',
			%options
		);
		#return undef if ($dupe eq 'err');
		return undef;
	}
	$self->{urls}{$class}{$url} = 1;

	return 1;
}

sub check_response_errors {
	my ($self, %options) = @_;

	my $res = $options{response} || confess "response object not provided";
	delete $options{response};

	my @response_host = $res->header('host');
	return undef if (! @response_host);

	my $errors = 0;

	# ---------- duplicate response hosts

	if (@response_host > 1) {
		$self->add_message(
			kind => 'warn',
			detail => 'response host header has multiple values',
			value => join (', ', @response_host),
			%options
		);
		$errors++;
	}

	# --------- response_host == api?

	if (@response_host == 1) {
		my $response_host = join (', ', @response_host);
		my $check = "//$response_host";
		my $api_url = $options{api_url};

		if ($api_url =~ /$check/) {
			# ok
		} else {
			$self->add_message(
				kind => 'warn',
				detail => 'response host does not match queried host',
				response_host => $response_host,
				%options
			);
			$errors++;
		}
	}

	# ---------- done

	if ($errors) {
		return undef;
	}

	return 1;
}

sub version_cleanup {
	my ($self, $version) = @_;

	return undef if (! defined $version);

	$version =~ s/-dirty//;
	$version =~ s/-\d\d-[a-z0-9]*$//;
	$version =~ s/-[a-z]*$//;

	return $version;
}

sub run_request {
	my ($self, $req, $options) = @_;

	$self->ua->dbh ($self->dbh);
	$self->ua->options ($options);

	my $res = $self->ua->request ($req);

	if ($$options{elapsed_time} > $$options{request_timeout}) {
		$self->add_message(
			kind => 'err',
			detail => 'response took longer than expected',
			%$options
		);
	}

	return $res;
}

1;
