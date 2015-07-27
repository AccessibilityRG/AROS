#!/usr/bin/perl

# Version 2012-03-18

use strict;
use locale;
use lib "/opt/shanke_lib/";

use HY::Geo::ttgetdb;
use HY::Geo::ttmsg;
use Config::IniFiles;
use DateTime::TimeZone;
use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use POSIX qw(locale_h);
use POSIX qw(strftime);

# Ini file to read
my $INIFILE = "./messages.ini";

# TTMSG parameter names - this array should contain all variable
# names inside Message section.

my @TTMSG_PARAM_NAMES = ('sms_user', 'sms_api_id', 'from', 'subject',
	'replace_8bit_sms', 'cost_route_sms');

my $cfg = Config::IniFiles->new(
	-file => $INIFILE,
	-nocase => 1);

# Read global settings from INI object

# Database settings
my $DB_DBI = $cfg->val('database','dbi');
my $DB_USERNAME = $cfg->val('database', 'username');
my $DB_PASSWORD = $cfg->val('database', 'password');

# SMS settings
my $DEBUG_LEVEL = $cfg->val('sms','debug_level',2);
my $DEBUG_CSV = $cfg->val('sms','debug_csv');
my $SMS = $cfg->val('sms', 'message','No message defined');
my $MAX_TIMESTAMPDIFF_LIMIT = $cfg->val('sms','max_timestampdiff', 0);

my %TARGET_NAMES = ();
foreach my $targets ($cfg->val('sms', 'target')) {
	my ($target, $route) = split(/,/, $targets);
	$TARGET_NAMES{$target} = $route;
	}

# Message settings (outbound SMS and email)
# Using @TTMSG_PARAM_NAMES instead of $cfg->Parameters('message')
# since the latter broke down at AUG-2012

my %TTMSG_PARAM = ();
foreach my $tt_param (@TTMSG_PARAM_NAMES) {
	$TTMSG_PARAM{uc($tt_param)} = $cfg->val('message', $tt_param);
	}

# sms-specific message settings
if ($cfg->val('sms', 'from')) {
	$TTMSG_PARAM{'FROM'} = $cfg->val('sms', 'from');
	}
if ($cfg->val('sms', 'subject')) {
	$TTMSG_PARAM{'SUBJECT'} = $cfg->val('sms', 'subject');
	}

# Timezone settings	
my $TIMEZONE_DIFF = $cfg->val('timezone','diff',0);

# Upstream/downstream texts
my $DIRECTION_UP = $cfg->val('sms', 'direction_up');
my $DIRECTION_DOWN = $cfg->val('sms', 'direction_down');

=encoding utf8

=head1 SYNOPSIS

perl sms.pl

=head1 DESCRIPTION

sms.pl takes last location of targets from table C<ttget> and tries to match
their coordinates to stationary locations defined in table C<locations>.

If some target is inside the area of a location, the script checks from table
C<target_locations> if the target has arrived into a new area. If the location
has really changed (and not remained as same) the SMS messages are sent.

The SMS messages are sent to those contacts (table C<contacts>) whose parameters
C<id_target> and C<id_location> fit to the observed pair.

Example:

Following contacts are defined in C<contacts>:
 Contact1   C<id_target>=NULL   C<id_location>=L2
 Contact2   C<id_target>=T1     C<id_location>=NULL
 Contact3   C<id_target>=T1     C<id_location>=L1

1) Target "T1" arrives into location "L1": The SMS is sent to Contact2 (target matches
and location is NULL so it matches to all locations) and Contact 3 (target and location
matches). Contact1 is not notified since location does not match (target NULL would match
to all targets).

2) Target "T2" arrives into location "L2": The SMS is sent to Contact1 (location
matches and target location NULL matches to all targets). Other contacts do not match.

=head1 CONFIGURATION

Configuration is read from INI file defined with variable C<$INIFILE>. The
file path is defined in the top lines of the file:

 # Ini file to read
 my $INIFILE = "./ttget.ini";

The file treated as case-insensitive the parameter name "dbi", "DBI" and "Dbi" are
the same.

=head1 NOTES CONCERNING DEBUG_CSV

The DEBUG_CSV setting sets the filename for CSV debug file. If the value is not set
with direct assignment (i.e. DEBUG_CSV is not defined) its value is tried to read
from environment variable DEBUG_CSV:

 $ DEBUG_CSV=some_file.csv perl sms.pl

Each human-readable
debug message produces also a CSV message to be appended to the file. The
fields are separated with ";". The fields are:

=over 4

=item 0: I<time_exec> (time of execution, e.g. "Thu Oct 13 21:23:25 2011")

=item 1: I<target_id> (e.g. "MS_Suomenlinna")

=item 2: I<current_lat> (e.g. 59.83527)

=item 3: I<current_lon> (e.g. 25.76456)

=item 4: I<current_timestamp> (Spot timestamp, e.g. "2011-08-22T19:51:44.000Z")

=item 5: I<route_id> (e.g. 1)

=item 6: I<nearest_routepoint> (e.g. 254)

=item 7: I<route_id + _ + nearest_routepoint> (e.g. "1_254")

=item 8: I<nearest_location> (e.g. "Hammarby")

=item 9: I<nearest_location_routepoint> (e.g. 360)

=item 10: I<route_id + _ + nearest_location_routepoint> (e.g. "1_360")

=item 11: I<last_location> (e.g. "Toresö")

=item 12: I<last_location_routepoint> (e.g. 265)

=item 13: I<last_location_timestamp> (Spot timestamp, e.g. "2011-08-22T19:41:42.000Z")

=item 14: I<route_id + _ + last_location_routepoint> (e.g. "1_265")

=item 15: I<message> (message string, see below, e.g. "SMS SENT")

=back

CSV log is updated by C<report_debug_csv()>.

=cut

report_debug("TTmsg sms.pl started", 2);

if (!defined($DEBUG_CSV) and $ENV{'DEBUG_CSV'} ne '') {
	$DEBUG_CSV = $ENV{'DEBUG_CSV'};
	}

# Create $ttget instance to access ttget database
my $ttget = HY::Geo::ttgetdb->new(DBI=>$DB_DBI, USER=>$DB_USERNAME, PASS=>$DB_PASSWORD);

# Set timezone
$ttget->time_difference($TIMEZONE_DIFF);

# Set charset
$ttget->set_cset('utf8');

# Set CSV filehandle as a global variable. See report_debug_csv() for more.
my $fh_csv;

# Location ID for unknown location
my $UNKNOWN_LOCATION = '__UNKNOWN__';

# Create $ttmsg instance to send messages
my $ttmsg = HY::Geo::ttmsg->new(%TTMSG_PARAM);

# Go through each moving target
foreach my $this_target (keys %TARGET_NAMES) {
	report_debug("Starting with target '".$this_target."' on route ".$TARGET_NAMES{$this_target}, 5);
	
	# Check for database errors
	if ($ttget->error_count() > 0) {
		report_error("Database errors exist, error count: ".$ttget->error_count(), 1);
		}
		
	# Check for ttmsg errors
	if ($ttmsg->error_count() > 0) {
		report_error("TTmsg errors exist, error count: ".$ttmsg->error_count(), 1);
		}
		
	# CSV debug array (see $DEBUG_CSV)
	my @dcsv = ();
	
	my $route_id = $TARGET_NAMES{$this_target};
	
	my @target_loc = $ttget->get_last_active_location($this_target);
	$dcsv[0] = localtime(time);	# CSV: time_exec
	$dcsv[1] = $this_target;	# CSV: target_id
	$dcsv[5] = $route_id;	# CSV: route_id
	$dcsv[7] = $route_id.'_'.$this_target;	# CSV: route_id + '_' + target_id
	
	report_debug("Target '$this_target' LAT: ".$target_loc[0]." LON: ".$target_loc[1]." TIME: ".$target_loc[2]." TIMESTR: ".gmtime($target_loc[2]), 5);

	$dcsv[2] = $target_loc[0];	# CSV: current_lat
	$dcsv[3] = $target_loc[1];	# CSV: current_lon
	$dcsv[4] = scalar(localtime($target_loc[2]));	# CSV: current_timestamp
	
	if ($target_loc[2] eq '') {
		report_debug("Target '$this_target' timestamp is empty, skipping", 4);
		$dcsv[15] = 'Timestamp empty';
		report_debug_csv(@dcsv);
		# End this cycle (skip to next target)
		next;
		}
		
	# Get last known location data
	my %last_location = $ttget->get_last_target_in_location($route_id, $this_target);
	
	# If last known location is empty (unknown location) use $UNKNOWN_LOCATION
	if ($last_location{'id_location'} eq '') {
		report_debug("Location ID was empty, substituting with $UNKNOWN_LOCATION", 5);
		$last_location{'id_location'} = $UNKNOWN_LOCATION;
		}
		
	$dcsv[11] = $last_location{'id_location'};	# CSV: last_location
	$dcsv[12] = $last_location{'routepoint'};	# CSV: last_location_routepoint
	$dcsv[13] = $last_location{'data_time'};	# CSV: last_location_timestamp
	$dcsv[14] = $route_id.'_'.$last_location{'routepoint'};	# CSV: route_id + _ + last_location_routepoint
	
	if (exists $last_location{'error'}) {
		# Errors present
		foreach my $this_error ($ttget->get_errors()) {
			report_error("Database error: ".$this_error);
			}
	
		# End this cycle (skip to next target)
		next;
		}

	# Get nearest routepoint data
	my %nearest_routepoint = $ttget->find_nearest_location($TARGET_NAMES{$this_target}, @target_loc);

	$dcsv[6] = $nearest_routepoint{'routepoint'};	# CSV: nearest_routepoint
	$dcsv[7] = $route_id.'_'.$nearest_routepoint{'routepoint'};	# CSV: route_id + '_' + nearest_routepoint
	$dcsv[8] = $nearest_routepoint{'location_nearby'}; # CSV: nearest_location

	# If there is no last known location data, store this one and skip to next target
	if ($last_location{'id_location'} eq '') {
		# There is no last known location for this target
		
		# Store current location as last known location
		$ttget->add_target_in_location(
			$route_id,
			$this_target,
			$nearest_routepoint{'location_nearby'},
			$nearest_routepoint{'routepoint'},
			$target_loc[2]);
		
		report_debug("Target '$this_target' has no last known location. Creating one. No SMS will be sent.", 4);
		$dcsv[15] = 'No last known location';
		report_debug_csv(@dcsv);
		
		# End this cycle (skip to next target)
		next;
		}
	
	# If this timestamp equals to the timestamp of the last known location
	# we are dealing with the same Spot entry (target has not reported fresh
	# location) -> skip
	
	if ($target_loc[2] == $last_location{'data_time'}) {
		report_debug("Target '$this_target' has equal timestamp with the previous one. Skipping.", 4);
		$dcsv[15] = 'No updated record - the current timestamp is equals with the previous one';
		report_debug_csv(@dcsv);

		# End this cycle (skip to next target)
		next;
		}
		
	# Now
	# - we know that the target has moved to another location since the
	#   last execution
	# - we have the last location in %last_location
	# - we have the current location in @target_loc and %nearest_routepoint
	
	# Store the current location
	$ttget->add_target_in_location(
		$route_id,
		$this_target,
		$nearest_routepoint{'location_nearby'},
		$nearest_routepoint{'routepoint'},
		$target_loc[2]);
	
	# If nearest routepoint does not have nearby_location, we are not
	# approaching any location -> skip
	if (!defined($nearest_routepoint{'location_nearby'}) or $nearest_routepoint{'location_nearby'} eq '') {
		report_debug("Target '$this_target' is not nearby any location, skipping", 4);
		$dcsv[15] = 'No nearby location';
		report_debug_csv(@dcsv);

		# End this cycle (skip to next target)
		next;
		}
		
	# Is the time difference between old and current data too long?
	# If so, store current location data with unknown location ID and stop
	
	if ($MAX_TIMESTAMPDIFF_LIMIT and 
		(abs($target_loc[2] - $last_location{'data_time'}) > $MAX_TIMESTAMPDIFF_LIMIT)) {
		
		report_debug("Target '$this_target' has too long difference in timestamps between current location ".
			"(".scalar(gmtime($target_loc[2])).") and previous location ".
			"(".scalar(gmtime($last_location{'data_time'}))."), skipping", 4);
		$dcsv[15] = 'Time difference is too long';
		report_debug_csv(@dcsv);

		# End this cycle (skip to next target)
		next;
		}

	# Has the location changed? If not, skip
	if ($last_location{'id_location'} eq $nearest_routepoint{'location_nearby'}) {
		report_debug("Target '$this_target' is still in the same location '".
			$last_location{'id_location'}."', skipping", 4);
		$dcsv[15] = 'Still in the same location';
		report_debug_csv(@dcsv);
		
		# End this cycle (skip to next target)
		next;
		}
	
	# At this point we know that our target has moved to a new location

	my %nearest_location_data =
		$ttget->get_location_routepoint($route_id, $nearest_routepoint{'location_nearby'});
	
	$dcsv[9] = $nearest_location_data{'routepoint'};	# CSV: nearest_location_routepoint
	$dcsv[10] = $route_id.'_'.$nearest_location_data{'routepoint'};	# CSV: route_id + _ + nearest_location_routepoint
			
	# Have we already passed the location routepoint?
	# If so -> skip

	my $direction;
	
	if ($last_location{'routepoint'} < $nearest_routepoint{'routepoint'}) {
		# We are coming from a smaller routepoint to a larger routepoint
		$direction = $DIRECTION_UP;
		
		if ($nearest_location_data{'routepoint'} < $nearest_routepoint{'routepoint'}) {
			# We have already passed the location
		
			report_debug("Target '$this_target' has already passed (direction: increasing routepoints) location ".
				$nearest_routepoint{'location_nearby'}." - ".
				"last routepoint: ".$last_location{'routepoint'}.", ".
				"current routepoint: ".$nearest_routepoint{'routepoint'}.", ".
				"direction: ".$direction.", ".
				"location routepoint: ".$nearest_location_data{'routepoint'}.". Skipping.", 4);
			$dcsv[15] = 'Location already passed - direction: increasing routepoints';
			report_debug_csv(@dcsv);

			# End this cycle (skip to next target)
			next;
			}
		}	
	elsif ($last_location{'routepoint'} > $nearest_routepoint{'routepoint'}) {
		# We are coming from larger routepoint to smaller routepoint
		$direction = $DIRECTION_DOWN;
		
		if ($nearest_location_data{'routepoint'} > $nearest_routepoint{'routepoint'}) {
			# We have already passed the location
		
			report_debug("Target '$this_target' has already passed (downstream) location ".
				$nearest_routepoint{'location_nearby'}." - ".
				"last routepoint: ".$last_location{'routepoint'}.", ".
				"current routepoint: ".$nearest_routepoint{'routepoint'}.", ".
				"direction: ".$direction.", ".
				"location routepoint: ".$nearest_location_data{'routepoint'}.". Skipping.", 4);
			$dcsv[15] = 'Location already passed - direction: decreasing routepoints';
			report_debug_csv(@dcsv);

			# End this cycle (skip to next target)
			next;
			}
		}
		
	# Count distance between us (the nearest routepoint) and the location
	my $distance = abs($nearest_routepoint{'distance'} - $nearest_location_data{'distance'});
	
	report_debug("Target '$this_target' arrives from ".
		$last_location{'id_location'}." at ".
		$nearest_routepoint{'location_nearby'}.", ".
		"direction: ".$direction, 4);
	report_debug("Nearest routepoint: id_route=".$route_id.", ".
		"routepoint=".$nearest_routepoint{'routepoint'}.", ".
		"distance=".$nearest_routepoint{'distance'}, 4);
	report_debug("Nearest location: id_route=".$route_id.", ".
		"routepoint=".$nearest_location_data{'routepoint'}.", ".
		"distance=".$nearest_location_data{'distance'}, 4);

	$dcsv[15] = 'Sending SMS: location changed from '.
		$last_location{'id_location'}.' to '.
		$nearest_routepoint{'location_nearby'}.' - distance: '.
		$distance.' - direction: '.$direction;
	report_debug_csv(@dcsv);
	
	report_changed_location($route_id, $this_target,
		$nearest_routepoint{'location_nearby'}, $distance,
		$direction, $target_loc[2]);
	}

$ttget->disconnect();

report_debug("TTmsg sms.pl finished normally", 2);

exit;

=head1 FUNCTIONS

=over 4

=item report_changed_location

This sub is called whenever a moving target (C<id> in table C<ttget>) has found in
new location (table C<locations>). Parameters: route ID, target ID, new
location ID, distance to the location and direction of the movement.

The subroutine find relevant contacts from table C<contacts> and notifies them
using C<HY::Geo::ttmsg>.

Returns true if message(s) was sent.

=cut

sub report_changed_location {
	my ($route, $target, $new_location, $distance, $direction, $timestamp) = @_;

	if ($new_location eq $UNKNOWN_LOCATION) {
		report_debug("Do not send SMS related to unknown location $new_location - skipping", 4);
		return;
		}
			
	# Round distance to one decimal
	
	$distance = sprintf("%.0f", $distance);
	
	# Enum contacts interested in $target AND $new_location
	my @contacts = $ttget->enum_contacts($route, $target, $new_location);
	
	# Store default locale
	my $default_locale = setlocale(LC_TIME);
	
	foreach my $this_contact (@contacts) {
		# Revert locale to default value
		setlocale(LC_TIME, $default_locale);
		
		# This value will be adjusted according to user's timezone setting
		my $timestamp_tz = $timestamp;
		
		# Check that given timezone is valid
		my $timezone_is_valid = undef;
		
		foreach my $this_tz (DateTime::TimeZone->all_names) {
			if ($this_tz eq $this_contact->{'timezone'}) {
				$timezone_is_valid = 1;
				}
			}
			
		if ($timezone_is_valid) {
			# Create DateTime::TimeZone object for user's timezone
			my $tz = DateTime::TimeZone->new(name => $this_contact->{'timezone'});

			# DateTime object
			my $dt = DateTime->from_epoch(
				epoch => $timestamp, time_zone => "GMT"
				);
			
			# Count contact's own $timestamp_tz from $timestamp ($dt)
			$timestamp_tz = $timestamp + $tz->offset_for_local_datetime($dt);
			}
		else {
			# User's timezone setting is not valid timezone string
			
			report_debug('Contact "'.$this_contact->{'name'}.'" has invalid timezone setting '.
				'"'.$this_contact->{'timezone'}.'". No timezone adjustment will be done.');
			}
		
		# Set current locale (if set)
		if ($this_contact->{'locale'}) {
			setlocale(LC_TIME, $this_contact->{'locale'});
			
			if (setlocale(LC_TIME) ne $this_contact->{'locale'}) {
				report_debug('Contact "'.$this_contact->{'name'}.'" has invalid locale setting '.
					'"'.$this_contact->{'locale'}.'". Default locale "'.$default_locale.'" will be used.');
				}
			}
		
		# Format time and date
		# Fallback: use default format for current locale
		my $timestamp_tz_time = strftime('%X', gmtime($timestamp_tz));
		my $timestamp_tz_date = strftime('%x', gmtime($timestamp_tz));
		
		if ($this_contact->{'fmt_time'}) {
			# Contact-specific format exists for time
			$timestamp_tz_time = strftime($this_contact->{'fmt_time'}, gmtime($timestamp_tz));
			}
		
		if ($this_contact->{'fmt_date'}) {
			# Contact-specific format exists for date
			$timestamp_tz_date = strftime($this_contact->{'fmt_date'}, gmtime($timestamp_tz));
			}
		
		# Build SMS from template
		my $this_sms = $SMS;
		$this_sms =~ s/#TARGET#/$target/ig;
		$this_sms =~ s/#LOCATION#/$new_location/ig;
		$this_sms =~ s/#DISTANCE#/$distance/ig;
		$this_sms =~ s/#DIRECTION#/$direction/ig;
		$this_sms =~ s/#TIME#/$timestamp_tz_time/ig;
		$this_sms =~ s/#DATE#/$timestamp_tz_date/ig;
		
		report_debug('Contact "'.$this_contact->{'name'}.'" '
			.'will be notified to "'.$this_contact->{'number'}.'": '.$this_sms,3);
		
		$ttmsg->send($this_contact->{'number'}, $this_sms);
		if ($ttmsg->error_count() > 0) {
			report_debug('Sending message to contact "'.$this_contact->{'name'}.'" '
				.'to "'.$this_contact->{'number'}.'" failed: '.join('; '.$ttmsg->get_errors()), 1);
			}
		}
	
	return 1;
	}

=item report_error

Reports error to STDERR. Checks and prints errors from C<HY::Geo::ttgetdb>, if
present.

 report_error("This sucks");
 
=cut

sub report_error {
	my ($message) = @_;
	
	report_debug("FATAL ERROR: ".$message, 0);
	
	print STDERR localtime(time)."\t$message\n";
	
	if (defined($ttget) and $ttget->error_count() > 0) {
		print STDERR join("\n", $ttget->get_errors())."\n";
		}
	
	if (defined($ttmsg) and $ttmsg->error_count() > 0) {
		print STDERR join("\n", $ttmsg->get_errors())."\n";
		}

	return 1;
	}

=item report_debug

Writes debug messages to STDOUT if message level is equal or smaller than
the global variable C<$DEBUG_LEVEL>.

 my $DEBUG_LEVEL = 3;
 
 report_debug("This message will be printed", 3);
 report_debug("This message will not be printed", 4);
 report_debug("This message will be printed");
 
Parameters: message to print, message level. If message level is not defined
the message is printed regardless the C<$DEBUG_LEVEL>.

=cut

sub report_debug {
	my ($message, $level) = @_;
	
	if ($level <= $DEBUG_LEVEL) { print localtime(time)."\t$level\t$message\n"; }
	
	return 1;
	}

=item report_debug_csv

Writes debug CSV to CSV log file (defined with variable C<$DEBUG_CSV>).
Please call C<report_debug_csv_close()> before exiting the script.

Parameter: Array of variables to write to CSV file (see CONFIGURATION and C<$DEBUG_CSV>).
Returns: Always true

=cut

sub report_debug_csv {
	my (@csv) = @_;
	
	if (!defined($DEBUG_CSV)) {
		# CSV filename was not defined: the user does not want us to write CSV log
		
		return 1;
		}
	
	if (!defined($fh_csv) or tell($fh_csv) < 0) {
		# File was not opened so we must open it now
		
		open($fh_csv, ">>$DEBUG_CSV") or die("Could not open $DEBUG_CSV for append: $!");
		flock($fh_csv, LOCK_EX) or die("Could not get exclusive lock to $DEBUG_CSV: $!");
		seek($fh_csv, 0, SEEK_END) or die("Could not seek to EOF of file $DEBUG_CSV: $!");
		}
	
	print $fh_csv join(';', @csv)."\n";
	
	return 1;
	}


=item report_debug_csv_close

Closes CSV log file. Should be called before exiting the script.

=back

=cut

sub report_debug_csv_close {
	if (defined($DEBUG_CSV) and tell($fh_csv) >= 0) {
		flock($fh_csv, LOCK_UN);
		close($fh_csv);
		}
	
	return 1;
	}
