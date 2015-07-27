sms
===

Abstract
--------

*sms* follows targets in table `ttget` and finds nearest routepoint (see value routepoint in table `routes`). If the routepoint has value `location_nearby` set, it is nearby this 
location. These stationary location are routepoints in table routes that have value `id_location` set. The program uses table `target_locations` to store current locations.

When the target is approaching a location, the interested contacts are notified by SMS. Table `contacts` is used to get phone numbers of relevant contacts.

*spotget* is configured using `messages.ini` common for all AROS scripts.

Documentation
-------------

*sms* is documented in the POD way:</p>

`$ perldoc /opt/ttget/sms/sms.pl`

Following modules (that are not part of a typical Linux installation) are used:
* `HY::Geo:ttgetdb` - Interaction with database 
* `HY::Geo:ttmsg`- Sending notifications via SMS or email 
* `Config::IniFiles` [CPAN](http://search.cpan.org/perldoc?Config::IniFiles) - Used to process INI files.
* `DateTime::TimeZone` [CPAN](http://search.cpan.org/perldoc?DateTime::TimeZone) - Used to count contacts' timestamps for their timezones.

Flowchart 
---------

See `SMS_flowcart_v4.pdf`.
 
