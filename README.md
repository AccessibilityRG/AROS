# AROS scripts

This repository contains scripts used in article [Seasonal fluctuation of riverine navigation and accessibility in Western Amazonia: An analysis combining a cost-efficient GPS-based observation system and interviews](http://dx.doi.org/10.1016/j.apgeog.2015.07.003).

The system operation in a nutshell:

1. Each target carries a [Spot Satellite Messenger](http://international.findmespot.com/) which sends its location to Spot database via the satellite.
2. `spotget` retrieves the locations to the local MySQL database. This data was later used in the article.
3. `sms` notifies the end-users about the approaching targets.

## messages.ini

The `messages.ini` is common configuration file for all scripts. Some parameters are also read from the database (e.g. table `contacts`).

### Structure

The messages.ini is an Windows-style INI file based on sections, variables and their values. The section and value names are case-insensitive. The values are case-sensitive. The 
comments are marked with ";".

```
[Section 1]
	Variable1=value1
	Variable2=value2

[Section 2]
	VARIABLE1=value3
	variable2=value4
	; This line is a comment and will not be processed
	; variable3=value5  this is not processed
```

### Section "Database"

This section is used by `sms` and `watchdog`.

| name | purpose |
|------|---------|
| dbi | DBI of the ttget MySQL database. |
| username | Username for the database. |
| password | Password for the database. For NULL password do not define any value. |

### Section "Message"

This section is used by `sms` and `watchdog`.

These parameters are directly fed to `HY::Geo::ttmsg`. All variable names are transferred to uppercase and fed to `HY::Geo::ttmsg` constructor. For all settings available see 
`HY::Geo::ttmsg` documentation. This table summarises the common parameters.

| name | purpose |
|------|---------|
| sms_user | BulkSMS username. |
| sms_api_id | BulkSMS password. |
| from | From address to use when sending emails. The default address is nobody@nodomain. |
| subject | Subject to use when sending emails. The default subject is "Notification from ttmsg". The subject string should be in UTF-8. |
| replace_8bit_sms | Setting this to true turns on 8-bit replacement behaviour. This is useful when your application produces 8-bit messages but you want to send only 7-bit SMS messages.<br><br>The option replaces 8-bit characters with a-z equivalents for all outbound messages. Known characters are replaced with 7-bit correspondents. Unknown characters are replaced with \_ (underscore). |
| cost_route_sms | Sets BulkSMS cost_route parameter. For more information see [BulkSMS documentation](http://www.bulksms.co.uk/docs/eapi/submission/send_sms/). The default cost_route is 1 which is set by `Net::SMS::BulkSMS`. |

### Section "Timezone"

This section is used by `sms` and `watchdog`.

| name | purpose |
|------|---------|
| diff | The difference between Findmespot timezone and your local timezone. If your Findmespot timezone is set to GMT (which is the default) and your servers are in EET (GMT +2) you should set DIFF=2. Unit: hours. |

### Section "SMS"

| name | purpose |
|------|---------|
| debug_level | Selects level of human-readmable logging. 0 or `undef` means no messages will be printed, 5 (the max) prints all messages. Messages will be printed to STDOUT. For more information see perldoc of `sms` for `report_debug()`. |
| debug_csv | If set the value is used as a filename for CSV debug file. If the value is not set with direct assignment (i.e. $DEBUG_CSV is not defined) its value is tried to read from environment variable DEBUG_CSV. For more information see perldoc of `sms`, "Notes concerning DEBUG_CSV". |
| message | The template for outbound messages (email or SMS). Following variables can be used:<br>#TARGET# Replaced with the target string.<br>#LOCATION# Replaced with the location string.<br>#DISTANCE# Replaced with the distance between current location of the target and the location.<br>#DIRECTION# Replaced with the correct direction tag (either value "direction_up" or "direction_down")<br>#TIME# Replaced with the last timestamp (time part) of the target's location. This timestamp is affected by contact's timezone (table "contacts" column "timezone"), time format (table "contacts" column "fmt_time") and contact's locale (table "contacts" column "locale).<br>#DATE# Replaced with the last timestamp (date part) of the target's location. This timestamp is affected by contact's timezone (table "contacts" column "timezone"), date format (table "contacts" column "fmt_date") and contact's locale (table "contacts" column "locale). |
| direction_up | If the target is moving upwards with the routepoint numbers the #DIRECTION# tag in the outbound message is replaced with this value. |
| direction_down | If the target is moving downwards with the routepoint numbers the #DIRECTION# tag in the outbound message is replaced with this value. |
| target | Defines a single target to follow. The script does not report all targets found in table ttget but only the ones defined by this directive. The value has following syntax: "target_name,route_id". To define multiple targets use multiple target definitions:<br>`target=Titanic,1`<br>`target=HMS Royal Oak,2`<br>`target=USS Yorktown,3` |
| max_timestampdiff | Skip pairs of timestamps if their timestamps differ more than MAX_TIMESTAMPDIFF. Generally this limits too old timstamps to result an SMS notification.<br>To skip all test regarding MAX_TIMESTAMPDIFF leave it undefined.<br>Unit: seconds |
| from | If set, overrides setting "from" from section "Message" when executing sms. |
| subject | If set, overrides setting "subject" from section "Message" when executing sms. |

### Section "Watchdog"

This section is used only by `watchdog`.

| name | purpose |
|------|---------|
| target | Defines a single target to follow. The script does not report all targets found in table ttget but only the ones defined by this directive. The value has following syntax: "target_name,route_id". To define multiple targets use multiple target definitions:<br>`target=Titanic,1`<br>`target=HMS Royal Oak,2`<br>`target=USS Yorktown,3` |
| message | The template for outbound messages (email or SMS). Following variables can be used:<br>#TARGET# Replaced with the target string<br>#TIMESTAMP# Replaced with the (outdated) timestamp |
| notify_limit | Notification limit in seconds. If the last active location of a target is older than notify_limit the notifications for this target will be sent. |
| debug_level | Set to 1 to turn debug messages on. |
| from | If set, overrides setting "from" from section "Message" when executing watchdog. |
| subject | If set, overrides setting "subject" from section "Message" when executing watchdog. |

### Section "Spotget"

This section use used by `spotget`.

| name | purpose |
|------|---------|
| browser_timeout | Browser timeout in seconds. Meaningful value is something between 10-30 seconds. Defaults to 10 seconds. |
| browser_id | Browser ID sent to web server (Spot API web server). Defaults to "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322)" |
| debug | Set this to 1 to get debug messages. |
| warning | Set this to 1 to get warning messages. |
| url | Spotget API URLs to follow. The URL value has three comma-separated fields:<br>1. Device ID that will be written to database ttget (e.g. "HENRY-7"). This does not have to have any correspondence with any of Spot site values.<br>2. Spot device ID that will be used to select data of the desired device (e.g. "0-7446484").<br>3. Spot API URL (see [Spot documentation](http://faq.findmespot.com/index.php?action=showEntry&data=69)). Note that you have to use XML URL:s (not JSON URL:s). |

Examples of meaningful values for `url`:

* url=HENRY,0-7446542,https://api.findmespot.com/spot-main-web/consumer/rest-api/2.0/public/feed/0eJnc9zXFKBVdvo4q5RlF1louqzjhdXYZ/message.xml
* url=HENRY,0-7446542,https://api.findmespot.com/spot-main-web/consumer/rest-api/2.0/public/feed/0eJnc9zXFKBVdvo4q5RlF1louqkjahXYZ/message.xml?feedPassword=123456

### Sample
```
[database]
	dbi=DBI:mysql:ttget
	username=webserver
	; no password (password is "undef")
	; password=
[message]
	; These parameters are directly fed to HY::Geo::ttmsg
	; For more information see HY::Geo::ttmsg::new
	sms_user=my_bulksms_username
	sms_api_id=my_bulksms_password
	from=nobody@domain.fi
	subject=TTget Notification
	replace_8bit_sms=1
[sms]
	debug_level=5
	; debug_csv=somefile.csv
	message=La embarcación #TARGET# está llegando a #LOCATION# (#DIRECTION#). La distancia es ahora #DISTANCE# kilometros.
	target=BOAT 1,1
	target=BOAT 2,2
	target=BOAT 3,3
	max_timestampdiff=172800
	direction_up=surcando
	direction_down=bajando
	[timezone]
	diff=2 	
```

## Database

The AROS scripts use MySQL database to store their data. This chapter explains the meaning of the fields. Some remarks can be found from the field comments. The complete SQL create 
code is in `database.sql`.


### ttget

This table contains data about the moving locations. The locations are added by cron-executed script `spotget` that parses locations from Findmespot web service.

| field name | description |
|------------|-------------|
| n | Index integer used for timestamp-independent ordering |
| id | ID of the moving location (target). This ID is referred in table `contacts` (variable `id_target`) and `target_locations` (`id_target`). |
| gettime | Timestamp for data retrieval. |
| lat, lon time, timegmtsec, esnname, messagetype | Raw data from Findmespot Shared Page XML feed. |

### route_legends

This table enumerates all route ID:s and their legends and descriptions. These ID:s a used in tables `routes` and `target_locations`.

| field name | description |
|------------|-------------|
| id | ID of the route. Integer, starts from 1. |
| legend | Short legend of the route. |
| description | Long description of the route. |

### routes

This table contains route points of all routes. The routes are defined in table `route_legends`.

| field name | description |
|------------|-------------|
| id_route | Route ID. Refers to table `route_legends`. |
| routepoint | Routepoints are ordered starting from 0. The routepoint 0 is called "origo". |
| distance | Distance of the routepoint from origo in kilometers. The routepoint 0 has distance 0 km etc. With this value you can count distance between every routepoint. |
| lat | Latitude in WGS84, e.g. "-5.22431". |
| lon | Longitude in WGS84, e.g. "-75.6754". |
| id_location | If this value is set, the routepoint is a stationary location (e.g. village, bus stop). This id_location is referred by `location_nearby` in this table, `id_location` in table `contacts` and `id_location` in table `target_locations`.
| location_nearby | If this value is set, the routepoint is nearby a location (refers to `id_location`). |

### contacts

This table contains data of the contacts to be informed about the movements of targets. The data is entered by hand. The field `last_sms` is updated by script `sms`.

Each entry is a rule with three conditions (route, target and location). If the script `sms.pl` notifies target A (table `ttget`) is approaching location area X (table `locations`) the 
script goes through all rules in this table. The contacts with matching rules (fields `id_route`, `id_target` and `id_location`) will be informed by SMS or email (see 
`HY::Geo::ttmsg`). Since NULL matches to all values a contact with values id_route=NULL, id_target=NULL, id_location=NULL would be notified concerning all approaches.


| field name | description |
|------------|-------------|
| passive | If value > 0, the contact is currently passive and should not receive any SMSs. |
| name | Contact name. This is a human-readable field and not referred by any other table. |
| number | Phone number in international format, e.g. "358505526766" or email address, e.g. "matti.lattu@helsinki.fi". Used to send messages through `HY::Geo::ttmsg`. |
| id_route | Route ID, refers to `id` in table `route_legends`. If set to NULL the contact is notified about all targets (NULL is like a wildcard *). |
| id_target | Refers to `id` in table `ttget`. This contact will be informed concerning actions related to this moving target. If set to NULL the contact is notified about all targets (NULL is like a wildcard *). |
| id_location | Refers to id_location in table routes. This contact will be informed concerning actions related to this stationary location. If set to NULL the contact is notified about all targets (NULL is like a wildcard *). Location ID "\_\_WATCHDOG\_\_" is a special code used by `watchdog`. |
| hours | If set, lists hours (comma-separated list without spaces) when contact wants to receive messages. For example string "9,10,11,12,13,14,15,16,17" allows messages to be sent only during office hours. If set to NULL the messages are sent regardless of current time (NULL is like a wildcard *). The time used here is the local time of the server. |
| timezone | Contact's timezone as Olson ID, e.g. "Europe/Helsinki", "America/Lima" ([browse legal values](http://twiki.org/cgi-bin/xtra/tzdatepick.html) or read [more thorough reference](http://www.twinsun.com/tz/tz-link.htm)). |
| locale | Contact's locale (e.g. "fi_FI.utf8"). Used to format date with strftime (see columns "fmt_time" and "fmt_date"). |
| fmt_time | Time format for outgoing messages. This value is fed into strftime so use [strftime format](http://www.manpagez.com/man/3/strftime/). |
| fmt_date | Date format for outgoing messages. This value is fed into strftime so use [strftime format](http://www.manpagez.com/man/3/strftime/). |
| last_sms | Timestamp of last SMS sent to this contact. *This value is not currently updated.* |
 						
### target_locations

This table stores data about the last known locations of a moving targets. The data is added (not updated or deleted) by script `sms`.

| field name | description |
|------------|-------------|
| n | Index integer used for timestamp-independent ordering |
| id_route | Route ID. Refers to tables `route_legends` and `routes`. |
| id_target | Specifies target (moving location). This refers to `id` in table `ttget`. |
| id_location | Specifies location (stationary location). This refers to `id_location` in table `routes`. |
| routepoint | Routepoint number of the last known location. Refers to value `routepoint` in table `routes`. |
| data_time | Original time string of the last known location. Cf. value time in table ttget. |
| addtime | Timestamp for the addition. |
