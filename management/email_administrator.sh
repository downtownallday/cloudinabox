#!/bin/bash
. /etc/cloudinabox.conf

if [ ! -x /usr/sbin/ssmtp ]; then
    # no ssmtp installed, so consume stdin and exit
    echo "email_administrator: ssmtp not installed or unavailable" 1>&2
    cat >/dev/null
    exit 1
fi

if [ -z "$ALERTS_EMAIL" ]; then
    # user has not configured ALERTS_EMAIL and does not want email notification
    cat >/dev/null
    exit 0
fi

subject="[$(hostname --fqdn)] $1"
admin_addr="$ALERTS_EMAIL"
tmp="/tmp/cloudinabox.$$.mail"

echo "Subject: $subject" > $tmp
echo "Content-Type: text/plain;charset=UTF-8" >>$tmp
echo "To: $ALERTS_EMAIL" >>$tmp
echo "" >>$tmp
echo "" >>$tmp
cat >>$tmp

# don't send the message if there are only headers
code=0
if [ $(awk 'BEGIN {C=0} $0 !~ /^[ \t]*$/ {C=C+1} END {print C}' $tmp) -gt 3 ]
then
    cat $tmp | /usr/sbin/ssmtp "$admin_addr"
    [ $? -ne -0 ] && code=1
fi

rm -f $tmp
exit $code
