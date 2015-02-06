#!/bin/sh
#
# Legacy action script for "service nginx upgrade"

# Source function library.
. /etc/rc.d/init.d/functions

prog=nginx
nginx=/usr/sbin/nginx
conffile=/etc/nginx/nginx.conf
pidfile=`/usr/bin/systemctl show -p PIDFile nginx.service | sed 's/^PIDFile=//' | tr ' ' '\n'`
SLEEPMSEC=100000
RETVAL=0

oldbinpidfile=${pidfile}.oldbin
${nginx} -t -c ${conffile} -q || return 6
echo -n $"Starting new master $prog: "
killproc -p ${pidfile} ${prog} -USR2
RETVAL=$?
echo
/bin/usleep $SLEEPMSEC
if [ -f ${oldbinpidfile} -a -f ${pidfile} ]; then
    echo -n $"Graceful shutdown of old $prog: "
    killproc -p ${oldbinpidfile} ${prog} -QUIT
    RETVAL=$?
    echo 
else
    echo $"Upgrade failed!"
    return 1
fi

exit $RETVAL
