package HY::Geo::ttgetdb;

# Version 2012-03-18

use strict;

use DBI;
use Encode;
use Time::Local;

=encoding utf8

=head1 SYNOPSIS

use HY::Geo::ttgetdb;

=head1 DESCRIPTION

HY::Geo::ttgetdb provides access to MySQL database populated by ttget (
L<http://harkko.lattu.biz/ttget/>), a tool
that fetches data from web resources.

In the project of Helsingin University
Department of Geosciences and Geography (L<http://www.helsinki.fi/geo/english/>)
ttget fetches location data from FindMeSpot geolocation service
(L<http://international.findmespot.com/>). The data is retrieved every fifteen
minutes and stored to MySQL database. C<ttgetdb> is used by the front-end tools
to retrieve that data.

=head1 METHODS

=over 4

=item new

Creates the ttgetdb object.

 my $ttdata1 = HY::Geo::ttgetdb->new(DBI=>'DBI:mysql:mydatabase',
    USER=>'myusername', PASS=>'mypassword');

 # MySQL has username with null password
 my $ttdata = HY::Geo::ttgetdb->new(DBI=>'DBI:mysql:mydatabase',
    USER=>'myusername');

Returns the object reference. Dies case of errors (missing required
parameters or failing to initialise database connection).

=cut

sub new {
	my ($class, %param) = @_;
	
	my $self = {};
	
	# Database handle
	$self->{'DBH'} = undef;
	
	if ($param{'DBI'} and $param{'USER'}) {
		# Required parameters exist
		
		$self->{'DBH'} = DBI->connect($param{'DBI'}, $param{'USER'}, $param{'PASS'},
			{RaiseError => 0, PrintError => 0});
		
		if (!$self->{'DBH'}) {
			die("HY::Geo::ttget could not initialise database connection: ".$DBI::errstr);
			}
		
		# Enable UTF8
		$self->{'DBH'}->{'mysql_enable_utf8'} = 1;
		$self->{'DBH'}->do('SET NAMES utf8;');
		}
	else {
		die("HY::Geo::ttgetdb->new was called without one of the required parameters DBI and USER. Please consult documentation.");
		return;
		}
	
	# see time_difference() and time_spot_to_unix()
	$self->{'SPOT_TIMEZONE'} = 0;
	
	# see enum_contacts_set_time()
	$self->{'ENUM_TIME'} = undef;
	
	$self->{'ERRORS'} = [];

	# Database charset, see cset()
	$self->{'DB_CHARSET'} = 'iso-8859-15';
	
	bless($self, $class);
	
	return $self;
	}

=item disconnect

Disconnects from database.

 $ttdata->disconnect();

=cut

sub disconnect {
	my ($class) = @_;
	
	$class->{'DBH'}->disconnect();
	
	return 1;
	}

=item insert_location_data

Inserts or updates location data for a certain tag. This method can be used
to insert new entries to location table.

Checks if existing data is found (SELECTs data with equal C<tag> and C<timegmtsec>
values) and effectively runs either of following SQL clauses:

 INSERT INTO ttget SET var1=val1, var2=val2, ...
 UPDATE ttget SET var1=val1, var2=var2, ... WHERE id=C<tag> AND timegmtsec=C<timegmtsec>

Example:

 my %data = (
    'id' => 'MyLocation', 'gettime' => '2012-03-11 07:15:09', 'lat' => '-3.72226',
    'lon' => '-73.2388', 'time' => '2012-03-10T14:16:31.000Z',
    'timegmtsec' => '1331388991', 'esnname' => 'Spot12', 'messagetype' => 'TRACK');
 my $ok = $ttget->insert_location_data(%data);
 if (!$ok) {
    print "Could not insert location data\n";
    print join("\n", $ttget->get_errors())."\n";
    }

Returns TRUE on success, FALSE on errors.

=cut

sub insert_location_data {
	my $class = shift;
	my %data = @_;
	
	# Remove all non-digits from "timegmtsec"
	$data{'timegmtsec'} =~ s/\D//g;
	
	# Check for existing record
	
	my $sql1 = 'SELECT id FROM ttget WHERE '.
		'id='.$class->{'DBH'}->quote($data{'id'}).' AND '.
		'timegmtsec='.$class->{'DBH'}->quote($data{'timegmtsec'});
		
	my $sth1 = $class->{'DBH'}->prepare($sql1);
	if (!$sth1) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql1.')');
		return;
		}
	
	if (!$sth1->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql1.')');
		return;
		}
	
	# Create SQL clause to UPDATE or INSERT
	
	# Join %data values my @data_values = ();
	my @data_values = ();
	foreach my $this_var (keys %data) {
		push(@data_values, $this_var.'='.$class->{'DBH'}->quote($data{$this_var}));
		}
	my $data_values_str = join(', ', @data_values);
	
	my $sql2;
	if ($sth1->rows > 0) {
		# There are existing record(s), update them
		
		$sql2 = 'UPDATE ttget SET '.$data_values_str.' WHERE '.
			'id='.$class->{'DBH'}->quote($data{'id'}).' AND '.
			'timegmtsec='.$class->{'DBH'}->quote($data{'timegmtsec'});
		}
	else {
		# There are no existing records, insert
		
		$sql2 = 'INSERT INTO ttget SET '.$data_values_str;
		}

	my $sth2 = $class->{'DBH'}->prepare($sql2);
	if (!$sth2) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql2.')');
		return;
		}
	
	if (!$sth2->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql2.')');
		return;
		}
	
	if ($sth2->rows > 0) {
		# Affected rows is more than one -> success
		return 1;
		}
	
	# Failed to add rows
	return;
	}

=item get_last_location_data

Get last location for certain tag. The location can be empty (i.e. location
data may be NULL). This method can be used i.e. to check that ttget cron job
is active and tries to fetch locations.

Effectively runs following SQL clause:

 SELECT from ttget WHERE id=C<$tag> ORDER BY timegmtsec DESC LIMIT 1;

Example:

 my %data1 = $ttget->get_last_location_data('MyDevice1');

C<get_last_location_data> takes two parameters: the device/location ID 
to look for.

Returns a hash containing the variables of the last record. Currently 
the keys are C<id>, C<gettime>, C<lat>, C<lon>, 
C<time>, C<timegmtsec>, C<esnname> and C<messagetype>.

=cut

sub get_last_location_data {
	my ($class, $tag) = @_;
	
	my $sql = 'SELECT * from ttget'
		.' WHERE id='.$class->{'DBH'}->quote($tag)
		.' ORDER BY timegmtsec DESC';
	
	return get_last_general($class, $sql);
	}

=item get_last_active_location_data

Like C<get_last_location()> but requires location to be valid (i.e. location
data may not be NULL). This method can be used to retrieve last valid location
of a device/location.

 SELECT * FROM ttget
   WHERE id=C<$tag> AND lat IS NOT NULL AND lon IS NOT NULL
   ORDER BY timegmtsec DESC;

Example:

 my %data1 = $ttget->get_last_active_location_data('MyDevice1');

The only required parameter is a tag to look for.

Returning values: see C<get_last_location()>.

=cut

sub get_last_active_location_data {
	my ($class, $tag) = @_;

	my $sql = 'SELECT * from ttget'
		.' WHERE id='.$class->{'DBH'}->quote($tag)
		.' AND lat IS NOT NULL AND lon IS NOT NULL'
		.' ORDER BY timegmtsec DESC LIMIT 1';

	return get_last_general($class, $sql);
	}

=item get_last_general

Primitive function for C<get_last_location()> and C<get_last_active_location>.

Parameter: SQL clause to find the expected record.

Returning values: see C<get_last_location()>.

=cut

sub get_last_general {
	my ($class, $sql) = @_;
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	my %data = ();
	
	while (my $ref = $sth->fetchrow_hashref()) {
		$data{'id'} = $class->cset($ref->{'id'});
		$data{'gettime'} = $class->cset($ref->{'gettime'});
		$data{'lat'} = $class->cset($ref->{'lat'});
		$data{'lon'} = $class->cset($ref->{'lon'});
		$data{'time'} = $class->cset($ref->{'time'});
		$data{'timegmtsec'} = $ref->{'timegmtsec'};
		$data{'esnname'} = $class->cset($ref->{'esnname'});
		$data{'messagetype'} = $class->cset($ref->{'messagetype'});
		}

	return %data;
	}

=item get_last_location

Like C<get_last_location_data> but returns only an array with location
and unix timestamp (C<timegmtsec>).

 my ($lat1, $lon1, $time1) = $ttget->get_last_location('MyDevice1');
 my ($lat2, $lon2, $time2) = $ttget->get_last_location('MyLocation1', 'locations');

Returns an array on success, false on error.

Note that the C<locations> table does not contain C<time> variable.
This is set as undef.

=cut

sub get_last_location {
	my ($class, $tag, $table) = @_;

	my %data = get_last_location_data($class, $tag, $table);
	
	if ($data{'id'} eq $tag) {
		# Retrieved ok
		
		return ($data{'lat'}, $data{'lon'}, $data{'timegmtsec'});
		}

	# Data retrieval failed
	add_error($class, 'get_last_location could not retrieve data for tag '.$tag);
	return undef;
	}

=item get_last_active_location

Like C<get_last_active_location_data> but returns only an array with location
and unix timestamp (C<timegmtsec>).

 my ($lat1, $lon1, $time1) =
   $ttget->get_last_active_location('MyDevice1');

Returns an array on success, false on error.

=cut

sub get_last_active_location {
	my ($class, $tag) = @_;

	my %data = get_last_active_location_data($class, $tag);
	
	if ($data{'id'} eq $tag) {
		# Retrieved ok
		
		return ($data{'lat'}, $data{'lon'}, $data{'timegmtsec'});
		}

	# Data retrieval failed
	return undef;
	}

=item find_nearest_location

Finds nearest location for a position.

 my $this_route_id = 1;
 my @location = $ttget->get_last_active_location('MyDevice1');

 my %nearest_routepoint =
   $ttget->find_nearest_location($this_route_id, @location);
 
Parameters: route id, current latitude, current longitude

Returns a hash with values from table C<routes>: C<routepoint>,
C<distance>, C<lat>, C<lon>, C<id_location> and C<location_nearby>.
If returns false, check errors with C<get_errors()>.

=cut

sub find_nearest_location {
	my ($class, $route_id, $cur_lat, $cur_lon) = @_;
	
	my $sql = 'SELECT *, '
		.'(111*SQRT(((lat-'.$cur_lat.')*(lat-'.$cur_lat.')) + '
		.'((lon-'.$cur_lon.')*(lon-'.$cur_lon.')))) AS target_distance '
		.'FROM `routes` where id_route='.$route_id.' ORDER BY target_distance ASC LIMIT 1';
		
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	my %data = ();
	
	while (my $ref = $sth->fetchrow_hashref()) {
		%data = %{$ref};
		
		# Correct charset
		$data{'id_location'} = $class->cset($data{'id_location'});
		$data{'location_nearby'} = $class->cset($data{'location_nearby'});
		}	

	return %data;
	}

=item enum_routes

Enumerates all routes from table C<route_legends>.

 my %routes = $ttget->enum_routes();
 foreach my $this_route (keys %routes) {
   print "Route $this_route legend: ".$routes{$this_route}{'legend'}."\n";
   print "Route $this_route description: ".$routes{$this_route}{'description'}."\n";
   }

C<enum_routes()> does not take any parameters. Returns a hash of
hash. First-level key is C<id_location>, second-level keys are
properties of this route, C<legend> and C<description>.

=cut

sub enum_routes {
	my ($class) = @_;
	
	my $sql = 'SELECT * FROM route_legends';
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	my %data = ();
	
	while (my $ref = $sth->fetchrow_hashref()) {
		$data{$ref->{'id_route'}} = $class->cset($ref->{'legend'});
		$data{$ref->{'id_route'}} = $class->cset($ref->{'description'});
		}	

	return %data;
	}

=item enum_locations

Enumerates all locations from the given route from table C<routes>. The valid
route IDs can be enumerated with C<enum_routes()>.

 my $route_id = 1;
 my %locations = $ttget->enum_locations($route_id);
 foreach my $this_location (keys %locations) {
   print "Location $this_location routepoint number: ".$locations{$this_location}{'routepoint'}."\n";
   print "Location $this_location distance: ".$locations{$this_location}{'distance'}."\n";
   print "Location $this_location latitude: ".$locations{$this_location}{'lat'}."\n";
   print "Location $this_location longitude: ".$locations{$this_location}{'lon'}."\n";
   }

The only parameter is route ID. Returns a hash of hash. First-level key is
C<id_location>, second-level keys are properties of this route:
C<routepoint>, C<distance>, C<lat> and C<lon>.

=cut

sub enum_locations {
	my ($class, $id_route) = @_;
	
	my $sql = 'SELECT * FROM routes WHERE id_route='.$id_route.' AND id_location IS NOT NULL';
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	my %data = ();
	
	while (my $ref = $sth->fetchrow_hashref()) {
		my $id_location = $class->cset($ref->{'id_location'});
		$data{$id_location}{'routepoint'} = $ref->{'routepoint'};
		$data{$id_location}{'distance'} = $ref->{'distance'};
		$data{$id_location}{'lat'} = $ref->{'lat'};
		$data{$id_location}{'lon'} = $ref->{'lon'};
		}	

	return %data;
	}

=item get_location_routepoint

Finds a routepoint of a location and returns its data.

 my $my_route = 3;
 my $my_location = "MyLocation3";
 my %data = $ttget->get_location_routepoint($my_route, $my_location);
 print "Routepoint number: ".$data{'routepoint'}."\n";
 print "Distance from starting point: ".$data{'distance'}." kilometers.\n";

Parameters: route ID and location ID.

Returns a hash with following variable from the table C<routes>:
C<routepoint>, C<distance>, C<lat> and C<lon>. If no location was found
returns undef.

=cut

sub get_location_routepoint {
	my ($class, $id_route, $id_location) = @_;
	
	my %data = enum_locations($class, $id_route);
	
	if (exists $data{$id_location}) {
		return %{$data{$id_location}};
		}
	else {
		return;
		}
	}
	
=item add_target_in_location

Adds last target location to database table C<target_locations>. This table holds
information about moving targets (in table C<ttget>) found in stationary locations
(defined in table C<locations>).

C<add_target_in_location()> and C<get_last_target_in_location()> can be used to store
location status between periodical jobs. For example if you check location of each
target every two hours the location can be stored with C<add_target_in_location()>.
In the next execution the script can check the last known location with
C<get_last_target_in_location()> to see if there has been changes.

There are five required parameters: route ID, target ID, location ID,
identified routepoint number and location timestamp as unix timestamp.

 my %last_location =
   $ttget->get_last_target_in_location($route_id, $this_target);
 
 if ($this_location ne $last_location{'id_location'}) {
   print "Target $this_target has moved from "
   	.$last_location{'id_location'}." to ".$this_location."\n";
   $ttget->add_target_in_location(
     $route_id, $this_target, $this_location, $this_routepoint, $this_time);
   }

Returns true on success, false on error.

=cut

sub add_target_in_location {
	my ($class, $route_id, $target, $location, $routepoint, $timestamp) = @_;

	my $sql = 'INSERT INTO target_locations SET '
		.'id_route='.$route_id.', '
		.'id_target='.$class->{'DBH'}->quote($class->cenc($target)).', '
		.'id_location='.$class->{'DBH'}->quote($class->cenc($location)).', '
		.'routepoint='.$routepoint.', '
		.'data_time='.$class->{'DBH'}->quote($timestamp);
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	return 1;
	}


=item get_last_target_in_location

Retrieves last known location of specified target. 

There are two required parameters: route ID and target ID.

 my %last_location =
   $ttget->get_last_target_in_location($this_route, $this_target);
   
 if (exists $last_location{'error'}) {
   print "Error while trying to get last know location:\n";
   print join("\n", $ttget->get_errors());
   }
 elsif ($last_location{'id_location'} eq '') {
   print "Target $this_target does not have last known location\n";
   }
 else ($last_location{'id_location'}) {
   print "Last location of target $this_target is $last_location\n";
   }

Returns a hash containing the last data from table C<target_locations>.
The hash has following keys: C<id_location>, C<routepoint>, C<data_time>
and C<addtime>. If C<id_location> is an empty string no last known location
was found. If the has has key C<error> there was an error
(see C<get_errors()>)

=cut

sub get_last_target_in_location {
	my ($class, $route_id, $target) = @_;
	
	my $sql = 'SELECT * FROM target_locations '
		.'WHERE id_route='.$route_id.' AND '
		.'id_target='.$class->{'DBH'}->quote(cenc($class,$target)).' '
		.'ORDER BY data_time DESC LIMIT 1';
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return ('error' => 1);
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return ('error' => 1);
		}
		
	my %location_data;
	
	while (my $ref = $sth->fetchrow_hashref()) {
		%location_data = ();
		$location_data{'id_location'} = $class->cset($ref->{'id_location'});
		$location_data{'routepoint'} = $ref->{'routepoint'};
		$location_data{'data_time'} = $ref->{'data_time'};
		$location_data{'addtime'} = $ref->{'addtime'};
		}	

	return %location_data;
	}

=item enum_contacts

Enumerate all active contacts from table C<contacts> that are interested in
certain set of C<id_route>, C<id_target> and C<id_location>. The search also
respects C<hours>, a comma-separated list of hours when contact wants to
receive messages. If contact's C<hours> is NULL the messages are sent
regardless of the time. The timezone is server's. Use C<enum_contacts_set_time()>
to override server's current time in the search.

Parameters: route ID (variable C<id> in table C<route_legends>), target ID
(variable C<id> in table C<ttget>) and location ID (variable C<id> in
table C<locations>). 

If the parameters C<target> and C<location> begin with __ (double underscore)
the NULL contacts do not match.

 my @contacts = $ttget->enum_contacts($id_route, $id_target, $id_location);

Returns an array of hashes where each array element has contact data in
following hash keys: C<name>, C<number>, C<last_sms>, C<timezone> and
C<timezone_offset>.

C<timezone> is the contact's timezone as Olson ID (see
L<http://www.twinsun.com/tz/tz-link.htm>). This can be used to make
timezone calculations with C<DateTime::TimeZone>. The returned timezone
string is not checked in any way so you must do this in the application level
(see C<DateTime::TimeZone->is_valid_name()>).

=cut

sub enum_contacts {
	my ($class, $route, $target, $location) = @_;
	
	my @rules = ();
	
	push(@rules, '(id_route='.$class->{'DBH'}->quote($route).' OR id_route IS NULL) ');
	
	if ($target =~ /^__/) {
		# Do not allow NULL match
		push(@rules, '(id_target='.$class->{'DBH'}->quote($target).')');
		}
	else {
		push(@rules, '(id_target='.$class->{'DBH'}->quote($target).' OR id_target IS NULL)');
		}
	
	if ($location =~ /^__/) {
		# Do not allow NULL match
		push(@rules, '(id_location='.$class->{'DBH'}->quote($location).')');
		}
	else {
		push(@rules, '(id_location='.$class->{'DBH'}->quote($location).' OR id_location IS NULL)');
		}

	# Hours rule
	my $this_hour;
	if (defined($class->{'ENUM_TIME'})) {
		# Time override was set
		my @time_arr = localtime($class->{'ENUM_TIME'});
		$this_hour = $time_arr[2];
		}
	else {
		# Time overrise was not set: use current time
		my @time_arr = localtime(time);
		$this_hour = $time_arr[2];
		}
	push (@rules, '(FIND_IN_SET('.$class->{'DBH'}->quote($this_hour).', hours) > 0 OR hours IS NULL)');
	
	my $sql = 'SELECT * FROM contacts '
		.'WHERE '.join(' AND ', @rules).' '
		.'AND NOT passive>0';
	
	my $sth = $class->{'DBH'}->prepare($sql);
	if (!$sth) {
		add_error($class, 'SQL error: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
	
	if (!$sth->execute) {
		add_error($class, 'SQL execute failed: '.$class->{'DBH'}->errstr.' ('.$sql.')');
		return;
		}
		
	my @contacts = ();
	
	while (my $ref = $sth->fetchrow_hashref()) {
		my %this_contact = ();
		$this_contact{'name'} = $class->cset($ref->{'name'});
		$this_contact{'number'} = $class->cset($ref->{'number'});
		$this_contact{'last_sms'} = $class->cset($ref->{'last_sms'});
		$this_contact{'timezone'} = $class->cset($ref->{'timezone'});
		$this_contact{'locale'} = $class->cset($ref->{'locale'});
		$this_contact{'fmt_time'} = $class->cset($ref->{'fmt_time'});
		$this_contact{'fmt_date'} = $class->cset($ref->{'fmt_date'});
		push(@contacts, {%this_contact});
		}

	return @contacts;
	}

=item enum_contacts_set_time

Sets time that overrides server's current time in C<enum_contacts()>.

Parameter: time as unix timestamp (set time) or C<undef> (unset time).

Returns always true.

=cut

sub enum_contacts_set_time {
	my ($class, $settime) = @_;
	
	$class->{'ENUM_TIME'} = $settime;

	return 1;
	}

=item time_difference

Sets difference between Findmespot timezone and your local timezone (see
C<time_spot_to_unix()>). According to the Findmespot FAQ
L<http://faq.findmespot.com/index.php?action=showEntry&data=559>
the default timezone is GMT. If your server happens to be in EET (GMT +2) you
can set the difference as follows:

 $ttget->time_difference(2);
 
The only parameter is time difference in hours. Returns always true.

=cut

sub time_difference {
	my ($class, $diff) = @_;
	
	$class->{'SPOT_TIMEZONE'} = $diff*3600;
	
	return 1;
	}
	
=item cset

Corrects database charset to Perl internal. Used when reading text
from database. Parameter: string from MySQL. Returns a string in Perl
internal format.

The database charset can be set with C<set_cset()>.

=cut

sub cset {
	my ($class, $text) = @_;
	
	#$text = encode("utf8", $text);
	$text = encode($class->{'DB_CHARSET'}, $text);

	return $text;
	}

=item cenc

Corrects Perl internal charset to database charset. Used when writing
text to database. Parameter: string to MySQL before C<DBD->quote()>.
Returns a string in MySQL charset.

The database charset can be set with C<set_cset()>.

=cut

sub cenc {
	my ($class, $text) = @_;
	
	$text = decode($class->{'DB_CHARSET'}, $text);
	
	return $text;
	}

=item set_cset

Sets database charset. See C<cset()>. Default charset is ISO-8859-15.
Parameter: Charset code (to list of codes see C<Encode> man page).

Returns always true.

=cut

sub set_cset {
	my ($class, $charset) = @_;

	$class->{'DB_CHARSET'} = $charset;

	return 1;
	}

=item add_error

Adds error to the array buffer. See C<get_errors()> and C<error_count()>.
Mainly for internal use.

 $ttget->add_error("The database connection has vanished");

Returns always true.

=cut

sub add_error {
	my ($class, $message) = @_;
	
	push(@{$class->{'ERRORS'}}, $message);
	
	return 1;
	}

=item get_errors

Empties and returns the error buffer array. See C<add_error()> and C<error_count()>.

 my @errors = $ttget->get_errors();
 
Returns the error array.

=cut

sub get_errors {
	my ($class) = @_;
	
	my @errors = @{$class->{'ERRORS'}};
	
	$class->{'ERRORS'} = [];
	
	return @errors;
	}

=item error_count

Returns the number of errors in the error buffer array. See C<add_error()> and
C<error_count()>.

 if ($ttget->error_count() > 0) {
   print STDERR "Errors present:\n";
   print join("\n", $ttget->get_errors());
   }
 else {
   print "No errors!\n";
   }

=cut

sub error_count {
	my ($class) = @_;
	
	return scalar(@{$class->{'ERRORS'}});
	}
	
1;

__END__

=back

=head1 BUGS

None.

=head1 AUTHOR

Matti Lattu, <matti@lattu.biz>

=head1 ACKNOWLEDGEMENTS

The code was created for the project FIXME.

=head1 LICENSE AND COPYRIGHT

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

Copyright (C) 2011-2012 Matti Lattu

=cut

