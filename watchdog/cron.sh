#!/bin/sh

cd /opt/ttget/watchdog/
LOG=/var/log/ttget/watchdog.log
NOW=`date`

echo "---Executing watchdog ${NOW}" >>${LOG}
perl watchdog.pl >>${LOG} 2>&1
NOW=`date`
echo "---Executed ${NOW}" >>${LOG}
