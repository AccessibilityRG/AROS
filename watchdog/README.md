watchdog
========

Follows table ttget for passive targets. Contacts with magic location ID "_WATCHDOG_" are notified.

Configuration
-------------

*spotget* is configured using `messages.ini` common for all AROS scripts.

Documentation
-------------

Watchdog is documented in the POD way:

`$ perldoc watchdog.pl`
 
Following modules (that are not part of standard installation) are used:
 
* `HY::Geo:ttgetdb` - Interaction with database
* `HY::Geo:ttmsg` - Sending notifications via SMS or email
* `Config::IniFiles` [CPAN](http://search.cpan.org/perldoc?Config::IniFiles) - Used to process INI files. 
