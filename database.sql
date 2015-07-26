CREATE DATABASE `ttget` /*!40100 DEFAULT CHARACTER SET latin1 */;

USE `ttget`;

CREATE TABLE `contacts` (
  `passive` int(11) NOT NULL COMMENT 'If value > 0, the contact is currently passive and should not receive any SMSes.',
  `name` varchar(64) collate utf8_swedish_ci NOT NULL COMMENT 'Contact name',
  `number` varchar(64) collate utf8_swedish_ci NOT NULL COMMENT 'Phone number in international format, e.g. "358505526766" or email address',
  `id_route` int(11) default NULL COMMENT 'Route ID, refers to "id" in table "route_legends". If set to NULL the contact is notified about all targets (NULL is like a wildcard *).',
  `id_target` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'Refers to id in table "ttget". This contact will be informed concerning actions related to this moving target.',
  `id_location` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'Refers to id in table "location". This contact will be informed concerning actions related to this stationary location.',
  `hours` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'If set, lists hours (comma-separated list) when contact wants to receive messages.',
  `timezone` varchar(40) collate utf8_swedish_ci default NULL COMMENT 'Timezone of the contact. Timezones are defined as Olson IDs (Continent/City). NULL refers to GMT.',
  `locale` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'Contacts locale setting, used for formatting time strings',
  `fmt_time` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'Time format in strftime format',
  `fmt_date` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'Date format in strftime format',
  `last_sms` datetime NOT NULL COMMENT 'Timestamp of last SMS message sent to this contact.'
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_swedish_ci COMMENT='Contacts and their links to locations.';

CREATE TABLE `route_legends` (
  `id_route` int(11) NOT NULL COMMENT 'Route ID. Refers to variable "id_route" in tables "routes" and "route_locations".',
  `legend` varchar(32) collate utf8_swedish_ci NOT NULL COMMENT 'Short legend of the route.',
  `description` text collate utf8_swedish_ci COMMENT 'Long description of the route.',
  PRIMARY KEY  (`id_route`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_swedish_ci COMMENT='Describes routes.';

CREATE TABLE `routes` (
  `id_route` int(11) NOT NULL COMMENT 'Refers to "id_route" in table "route_legends".',
  `routepoint` int(11) NOT NULL COMMENT 'Order number of the routepoint.',
  `distance` float NOT NULL COMMENT 'Distance in kilometers from origo.',
  `lat` float NOT NULL COMMENT 'Latitude in WGS84. Use "." instead of ",".',
  `lon` float NOT NULL COMMENT 'Longitude in WGS84. Use "." instead of ",".',
  `id_location` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'If set, the routepoint is location. The value specifies the name of the location. This value is referred from table "contacts" and "target_locations".',
  `location_nearby` varchar(32) collate utf8_swedish_ci default NULL COMMENT 'If set, the routepoint is around a location. Refers to value "id_location".'
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_swedish_ci COMMENT='Defines routes with an ordered serie of route points.';

CREATE TABLE `target_locations` (
  `n` bigint(20) unsigned NOT NULL auto_increment COMMENT 'Index integer used for timestamp-independent ordering',
  `id_route` int(11) NOT NULL COMMENT 'Refers to route IDs in "routes" and "route_legends".',
  `id_target` varchar(32) collate utf8_swedish_ci NOT NULL COMMENT 'Specifies target (moving location). This is one of the IDs in the table "ttget".',
  `id_location` varchar(32) collate utf8_swedish_ci NOT NULL COMMENT 'Specifies location (stationary location). This is one of the IDs in the table "locations".',
  `routepoint` int(11) NOT NULL COMMENT 'Routepoint number of the last known location. See table "route" value "routepoint".',
  `data_time` int(32) NOT NULL COMMENT 'Original time value of the last known location. Cf. table "ttget" value "timegmtsec".',
  `addtime` timestamp NOT NULL default CURRENT_TIMESTAMP COMMENT 'When the target was found in the location.',
  PRIMARY KEY  (`n`)
) ENGINE=MyISAM AUTO_INCREMENT=37710 DEFAULT CHARSET=utf8 COLLATE=utf8_swedish_ci COMMENT='Lists last known locations of targets.';

CREATE TABLE `ttget` (
  `n` bigint(20) unsigned NOT NULL auto_increment COMMENT 'Index integer used for timestamp-independent ordering',
  `id` varchar(32) collate utf8_swedish_ci NOT NULL,
  `gettime` varchar(32) collate utf8_swedish_ci default NULL,
  `lat` varchar(12) collate utf8_swedish_ci default NULL,
  `lon` varchar(12) collate utf8_swedish_ci default NULL,
  `time` varchar(32) collate utf8_swedish_ci default NULL,
  `timegmtsec` int(11) default NULL,
  `esnname` varchar(16) collate utf8_swedish_ci default NULL,
  `messagetype` varchar(16) collate utf8_swedish_ci default NULL,
  PRIMARY KEY  (`n`),
  KEY `n` (`n`)
) ENGINE=MyISAM AUTO_INCREMENT=319427 DEFAULT CHARSET=utf8 COLLATE=utf8_swedish_ci;

