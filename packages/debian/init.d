#!/bin/sh
### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $network $remote_fs $local_fs 
# Required-Stop:     $network $remote_fs $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Stop/start nginx
### END INIT INFO

# Author: Sergey Budnevitch <sb@nginx.com>

PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC=nginx
NAME=nginx
CONFFILE=/etc/nginx/nginx.conf
DAEMON=/usr/sbin/nginx
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME

[ -x $DAEMON ] || exit 0

[ -r /etc/default/$NAME ] && . /etc/default/$NAME

DAEMON_ARGS="-c $CONFFILE $DAEMON_ARGS"

. /lib/init/vars.sh

. /lib/lsb/init-functions

do_start()
{
    start-stop-daemon --start --quiet --pidfile $PIDFILE --exec $DAEMON -- \
        $DAEMON_ARGS
    RETVAL="$?"
    return "$RETVAL"
}

do_stop()
{
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME
    RETVAL="$?"
    rm -f $PIDFILE
    return "$RETVAL"
}

do_reload() {
    #
    start-stop-daemon --stop --signal HUP --quiet --pidfile $PIDFILE --name $NAME
    RETVAL="$?"
    return "$RETVAL"
}

do_configtest() {
    if [ "$#" -ne 0 ]; then
        case "$1" in
            -q)
                FLAG=$1
                ;;
            *)
                ;;
        esac
        shift
    fi
    $DAEMON -t $FLAG -c $CONFFILE
    RETVAL="$?"
    return $RETVAL
}

do_upgrade() {
    OLDBINPIDFILE=$PIDFILE.oldbin

    do_configtest -q || return 6
    start-stop-daemon --stop --signal USR2 --quiet --pidfile $PIDFILE --name $NAME
    RETVAL="$?"
    sleep 1
    if [ -f $OLDBINPIDFILE -a -f $PIDFILE ]; then
        start-stop-daemon --stop --signal QUIT --quiet --pidfile $OLDBINPIDFILE --name $NAME
        RETVAL="$?"
    else
        echo $"Upgrade failed!"
        RETVAL=1
        return $RETVAL
    fi
}

case "$1" in
    start)
        [ "$VERBOSE" != no ] && log_daemon_msg "Starting $DESC " "$NAME"
        do_start
        case "$?" in
            0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
            2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
    stop)
        [ "$VERBOSE" != no ] && log_daemon_msg "Stopping $DESC" "$NAME"
        do_stop
        case "$?" in
            0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
            2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
  status)
        status_of_proc "$DAEMON" "$NAME" && exit 0 || exit $?
        ;;
  configtest)
        do_configtest
        ;;
  upgrade)
        do_upgrade
        ;;
  reload|force-reload)
        log_daemon_msg "Reloading $DESC" "$NAME"
        do_reload
        log_end_msg $?
        ;;
  restart|force-reload)
        log_daemon_msg "Restarting $DESC" "$NAME"
        do_configtest -q || exit $RETVAL
        do_stop
        case "$?" in
            0|1)
                do_start
                case "$?" in
                    0) log_end_msg 0 ;;
                    1) log_end_msg 1 ;; # Old process is still running
                    *) log_end_msg 1 ;; # Failed to start
                esac
                ;;
            *)
                # Failed to stop
                log_end_msg 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $SCRIPTNAME {start|stop|status|restart|reload|force-reload|upgrade|configtest}" >&2
        exit 3
        ;;
esac

exit $RETVAL
