#!/bin/sh

# Aja ensin spotget (hakee koordinaatit)
/opt/ttget/spotget/cron.sh

# Aja sen jälkeen sms-lähetin
/opt/ttget/sms/cron.sh

