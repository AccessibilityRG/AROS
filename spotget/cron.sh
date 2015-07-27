#!/bin/sh

# cron ajaa tämän skriptin. Tämä ajaa spotget:n,
# joka hakee koordinaatit. Ks. /root/README_spotget.txt

cd /opt/ttget/spotget/
LOG=/var/log/ttget/spotget.log
LOCK=/var/lock/spotget.lock
NOW=`date`

# Älä tee mitään - korjataan skriptiä
#echo "---Not doing anything - repairs going on, ${NOW}" >>${LOG}
#exit

if [ "$1" = "debug" ]; then
	LOG=/dev/tty
fi

if [ -f $LOCK ]; then
	echo "---Not executing spotget, lock file exists ${NOW}" >>${LOG}
	exit 0
fi

echo "---Executing spotget ${NOW}" >>${LOG}
perl spotget.pl >>${LOG} 2>&1
NOW=`date`
echo "---Executed ${NOW}" >>${LOG}
