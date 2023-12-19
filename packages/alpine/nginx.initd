#!/sbin/openrc-run

description="Nginx http and reverse proxy server"
extra_commands="checkconfig"
extra_started_commands="reload reopen upgrade"

cfgfile=${cfgfile:-/etc/nginx/nginx.conf}
pidfile=/run/nginx/nginx.pid
command=/usr/sbin/nginx
command_args="-c $cfgfile"
required_files="$cfgfile"

depend() {
	need net
	use dns logger netmount
}

start_pre() {
	checkpath --directory --owner nginx:nginx ${pidfile%/*}
	$command $command_args -t -q
}

checkconfig() {
	ebegin "Checking $RC_SVCNAME configuration"
	start_pre
	eend $?
}

reload() {
	ebegin "Reloading $RC_SVCNAME configuration"
	start_pre && start-stop-daemon --signal HUP --pidfile $pidfile
	eend $?
}

reopen() {
	ebegin "Reopening $RC_SVCNAME log files"
	start-stop-daemon --signal USR1 --pidfile $pidfile
	eend $?
}

upgrade() {
	start_pre || return 1

	ebegin "Upgrading $RC_SVCNAME binary"

	einfo "Sending USR2 to old binary"
	start-stop-daemon --signal USR2 --pidfile $pidfile

	einfo "Sleeping 3 seconds before pid-files checking"
	sleep 3

	if [ ! -f $pidfile.oldbin ]; then
		eerror "File with old pid ($pidfile.oldbin) not found"
		return 1
	fi

	if [ ! -f $pidfile ]; then
		eerror "New binary failed to start"
		return 1
	fi

	einfo "Sleeping 3 seconds before WINCH"
	sleep 3 ; start-stop-daemon --signal 28 --pidfile $pidfile.oldbin

	einfo "Sending QUIT to old binary"
	start-stop-daemon --signal QUIT --pidfile $pidfile.oldbin

	einfo "Upgrade completed"

	eend $? "Upgrade failed"
}
