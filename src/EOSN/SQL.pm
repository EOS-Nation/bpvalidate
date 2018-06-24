package EOSN::SQL;

# --------------------------------------------------------------------------

use utf8;
use strict;
use Carp;
use DBI;
use Exporter;

use parent qw (Exporter);
our @EXPORT_OK = qw (do_connect);

my $drh = DBI->install_driver("mysql");

# --------------------------------------------------------------------------
# Subroutines

sub do_connect {
	my ($database, $user, $password, $host) = @_;

	if (! $database) {
		croak "No database specified";
	}

	my $dbh;
	my $i = 0;
	my $env_prefix = "MYSQL_DATABASE_" . uc($database);
	my $env_user = "${env_prefix}_USER";
	my $env_pass = "${env_prefix}_PASS";
	my $env_host = "${env_prefix}_HOST";

	if (! defined $user) {
		$user = $ENV{$env_user} || die "$0: $env_user is not defined";
	}

	if (! defined $password) {
		$password = $ENV{$env_pass} || die "$0: $env_pass is not defined";
	}

	if (! defined $host) {
		$host = $ENV{$env_host} || die "$0: $env_host is not defined";
	}

	while (! $dbh) {
		$i++;
		if ($i > 10) {
			croak "Cannot connect to the database: $!";
		}
		$dbh = DBI->connect("dbi:mysql:dbname=$database;host=$host", $user, $password, {mysql_enable_utf8 => 1, mysql_enable_utf8mb4 => 1});
		if (! $dbh) {
			warn "connect failed (attempt $i): " . $DBI::errstr . "\n";
			sleep 60;       # wait for the database to start up
		}
	}

	return $dbh;
}

1;
