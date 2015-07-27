#!/usr/bin/perl

use strict;
use lib "/opt/shanke_lib/";

use XML::Simple;
use HY::Geo::ttgetdb;
use Config::IniFiles;
use Data::Dumper;
use LWP::UserAgent;
use POSIX qw(strftime);

# Ini file to read
my $INIFILE = "./messages.ini";

my $cfg = Config::IniFiles->new(
	-file => $INIFILE,
	-nocase => 1);

# Read global settings from INI object

# Database settings
my $DB_DBI = $cfg->val('database','dbi');
my $DB_USERNAME = $cfg->val('database', 'username');
my $DB_PASSWORD = $cfg->val('database', 'password');

# Browser settings (and their default values)
my $BROWSER_TIMEOUT = $cfg->val('spotget', 'browser_timeout', 10);
my $BROWSER_ID = $cfg->val('spotget', 'browser_id', 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)');

# Output settings
my $DEBUG = $cfg->val('spotget', 'debug', undef);
my $WARNING = $cfg->val('spotget', 'warning', 1);

# URLs
my @url = ();
foreach my $this_url_cfg ($cfg->val('spotget','url')) {
	my @url_arr = split(/,/, $this_url_cfg);
	push(@url, {'id' => $url_arr[0], 'spot_id' => $url_arr[1], 'url' => $url_arr[2]});
	}
	
=encoding utf8

=head1 SYNOPSIS

perl spotget.pl

=head1 DESCRIPTION

spotget.pl reads locations from FindmeSpot XML API as explained
at L<http://faq.findmespot.com/index.php?action=showEntry&data=69>.
The script gets all configured SPOT URLs one at a time and decodes the
XML. The values are written to C<ttget> database. The existing values
(values with same C<id> and C<timegmtsec>) are updated with new values.

The script works with SPOT REST-API 2.0 XML that was introduced September 2012.
The URL format should be

L<https://api.findmespot.com/spot-main-web/consumer/rest-api/2.0/public/feed/FEED_ID_HERE/message.xml>

or with password

L<https://api.findmespot.com/spot-main-web/consumer/rest-api/2.0/public/feed/FEED_ID_HERE/message.xml?feedPassword=123456>

=head1 CONFIGURATION

Configuration is read from INI file defined with variable C<$INIFILE>. The
file path is defined in the top lines of the file:

 # Ini file to read
 my $INIFILE = "./messages.ini";

The file treated as case-insensitive the parameter name "dbi", "DBI" and "Dbi" are
the same.

=cut

# Create $ttget instance to access ttget database
my $ttget = HY::Geo::ttgetdb->new(DBI=>$DB_DBI, USER=>$DB_USERNAME, PASS=>$DB_PASSWORD);

# Create LWP::UserAgent object
# This is used as a global variable by http_get()
my $ua = LWP::UserAgent->new;
$ua->timeout($BROWSER_TIMEOUT);
$ua->agent($BROWSER_ID);

my $CURRENT_TIME = get_mysqltime();

# Create http cache (at the moment LWP::ConnCache is still experimental)
# This is used as a global variable by http_get()
my %http_cache = ();

for (my $i=0; $i<scalar(@url); $i++) {
	my $page = http_get($url[$i]{'url'});
	
	my $xml = XMLin($page);
	
	# print Dumper($xml);
	
	my $message_value;
	eval { $message_value = $xml->{'feedMessageResponse'}->{'messages'}->{'message'}; };
	
	if (!defined($message_value)) {
		# There is no value for XML tag 'message'
		tt_debug("No data for XML tag 'message', URL: ".$url[$i]{'url'}."\n");
		next;
		}
	
	# print Dumper($xml->{'feedMessageResponse'}->{'messages'}->{'message'});
	
	# Go through all messages, store data
	foreach my $this_data_id (keys %{ $xml->{'feedMessageResponse'}->{'messages'}->{'message'}}) {
		my $this_data = $xml->{'feedMessageResponse'}->{'messages'}->{'message'}->{$this_data_id};
		
		my $messenger_id = undef;
		eval { $messenger_id = $this_data->{'messengerId'}; };

		if (!defined($messenger_id)) {
			# XML contains entry without messengerId
			next;
			}

		if ($this_data->{'messengerId'} eq $url[$i]{'spot_id'}) {
			# The ESN ID is just what we wanted
			
			my %this_data = ();
			$this_data{'id'} = $url[$i]{'id'};
			$this_data{'gettime'} = $CURRENT_TIME;
			eval { $this_data{'lat'} = $this_data->{'latitude'}; };
			eval { $this_data{'lon'} = $this_data->{'longitude'}; };
			eval { $this_data{'time'} = $this_data->{'dateTime'}; };
			eval { $this_data{'timegmtsec'} = $this_data->{'unixTime'}; };
			eval { $this_data{'esnname'} = $this_data->{'messengerName'}; };
			eval { $this_data{'messagetype'} = $this_data->{'messageType'}; };
			
			if ($ttget->insert_location_data(%this_data)) {
				tt_debug("Data inserted for ID ".$url[$i]{'id'});
				}
			else {
				tt_error("Failed to insert location data for ID ".$url[$i]{'id'});
				foreach my $this_error ($ttget->get_errors()) {
					tt_error("DB error: ".$this_error);
					}
				}
			}
		}
	}
	
$ttget->disconnect();
exit;

=head1 SUBROUTINES

=item http_get

http_get() uses LWP::UserAgent to retrieve an URL given as the parameter. It
returns the retrieved data in a single variable.

http_get() uses its own cache. If the URL is found from a global variable
C<%http_cache> the HTTP GET is skipped and the cached page content is
returned.

http_get() uses a global C<$ua> LWP::UserAgent object.

On error returns undef.

Example:

 my $page = http_get('http://etunimi.fi');
 print $page;

=cut

sub http_get {
	my ($url) = @_;
	
	# $ua is global LWP::UserAgent object
	# %http_cache is a global cache hash (key = url)
	
	if ($http_cache{$url}) {
		# Content found from cache, return from cache
		return $http_cache{$url};
		}
	
	# Not found from cache, do HTTP GET
	my $response = $ua->get($url);
	
	if ($response->is_success) {
		# HTTP GET success
		
		# Update cache
		$http_cache{$url} = $response->decoded_content;
		
		# Return content
		return $response->decoded_content;
		}

	# HTTP GET failed
	return;		
	}

=item get_mysqltime

Returns current local timestamp on MySQL format YYYY-MM-DD HH:MM:SS.

=cut

sub get_mysqltime {
	return strftime("%Y-%m-%d %H:%M:%S", localtime);
	}

=item tt_debug

FIXME: Documentation missing

=cut

sub tt_debug {
	if ($DEBUG ne '') {
		print localtime(time)."\tDEBUG\t".$_[0]."\n";
		}
	}

=item tt_warn

FIXME: Documentation missing

=cut

sub tt_warn {
	if ($WARNING ne '') {
		print localtime(time)."\tWARN\t".$_[0]."\n";
		}
	}

=item tt_error

FIXME: Documentation missing

=cut

sub tt_error {
	print STDERR localtime(time)."\tERROR\t".$_[0]."\n";
	}
