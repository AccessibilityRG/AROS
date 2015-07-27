#!/bin/sh

# cron ajaa tämän skriptin puolen tunnin välein. Tämä ajaa ttget:n,
# joka katsoo onko ovatko liikkuvat kohteet paikallisten kohteiden
# lähettyvillä. Ks. /root/README_sms.txt

cd /opt/ttget/sms/
LOG=/var/log/ttget/sms.log
CSV=/var/log/ttget/sms.csv
LOCK=/var/lock/ttget.lock
NOW=`date`

if [ -f $LOCK ]; then
	echo "---Not executing sms, lock file exists ${NOW}" >>${LOG}
	exit 0
fi

echo "---Executing sms ${NOW}" >>${LOG}
DEBUG_CSV=${CSV} perl sms.pl >>${LOG} 2>&1
NOW=`date`
echo "---Executed ${NOW}" >>${LOG}
