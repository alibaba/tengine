#!/bin/sh
#
# nginx        Startup script for nginx
#
# chkconfig: - 85 15
# processname: nginx
# config: /etc/nginx/nginx.conf
# config: /etc/sysconfig/nginx
# pidfile: /var/run/nginx.pid
# description: nginx is an HTTP and reverse proxy server
#
### BEGIN INIT INFO
# Provides: nginx
# Required-Start: $local_fs $remote_fs $network
# Required-Stop: $local_fs $remote_fs $network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop nginx
### END INIT INFO

# Source function library.
. /etc/rc.d/init.d/functions

if [ -L $0 ]; then
    initscript=`/bin/readlink -f $0`
else
    initscript=$0
fi

sysconfig=`/bin/basename $initscript`

if [ -f /etc/sysconfig/$sysconfig ]; then
    . /etc/sysconfig/$sysconfig
fi

nginx=${NGINX-/usr/sbin/nginx}
prog=`/bin/basename $nginx`
conffile=${CONFFILE-/etc/nginx/nginx.conf}
lockfile=${LOCKFILE-/var/lock/subsys/nginx}
pidfile=${PIDFILE-/var/run/nginx.pid}
SLEEPMSEC=${SLEEPMSEC-200000}
UPGRADEWAITLOOPS=${UPGRADEWAITLOOPS-5}
RETVAL=0

start() {
    echo -n $"Starting $prog: "

    daemon --pidfile=${pidfile} ${nginx} -c ${conffile}
    RETVAL=$?
    echo
    [ $RETVAL = 0 ] && touch ${lockfile}
    return $RETVAL
}

stop() {
    echo -n $"Stopping $prog: "
    killproc -p ${pidfile} ${prog}
    RETVAL=$?
    echo
    [ $RETVAL = 0 ] && rm -f ${lockfile} ${pidfile}
}

reload() {
    echo -n $"Reloading $prog: "
    killproc -p ${pidfile} ${prog} -HUP
    RETVAL=$?
    echo
}

upgrade() {
    oldbinpidfile=${pidfile}.oldbin

    configtest -q || return
    echo -n $"Starting new master $prog: "
    killproc -p ${pidfile} ${prog} -USR2
    echo

    for i in `/usr/bin/seq $UPGRADEWAITLOOPS`; do
        /bin/usleep $SLEEPMSEC
        if [ -f ${oldbinpidfile} -a -f ${pidfile} ]; then
            echo -n $"Graceful shutdown of old $prog: "
            killproc -p ${oldbinpidfile} ${prog} -QUIT
            RETVAL=$?
            echo
            return
        fi
    done

    echo $"Upgrade failed!"
    RETVAL=1
}

configtest() {
    if [ "$#" -ne 0 ] ; then
        case "$1" in
            -q)
                FLAG=$1
                ;;
            *)
                ;;
        esac
        shift
    fi
    ${nginx} -t -c ${conffile} $FLAG
    RETVAL=$?
    return $RETVAL
}

rh_status() {
    status -p ${pidfile} ${nginx}
}

# See how we were called.
case "$1" in
    start)
        rh_status >/dev/null 2>&1 && exit 0
        start
        ;;
    stop)
        stop
        ;;
    status)
        rh_status
        RETVAL=$?
        ;;
    restart)
        configtest -q || exit $RETVAL
        stop
        start
        ;;
    upgrade)
        rh_status >/dev/null 2>&1 || exit 0
        upgrade
        ;;
    condrestart|try-restart)
        if rh_status >/dev/null 2>&1; then
            stop
            start
        fi
        ;;
    force-reload|reload)
        reload
        ;;
    configtest)
        configtest
        ;;
    *)
        echo $"Usage: $prog {start|stop|restart|condrestart|try-restart|force-reload|upgrade|reload|status|help|configtest}"
        RETVAL=2
esac

exit $RETVAL
