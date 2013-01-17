%define software tengine
%define nginx_user nobody
%define nginx_group nobody
%define nginx_home /usr/local/nginx
%define nginx_home_tmp  /usr/local/nginx/tmp

Name: %{software}
Version: 1.4.2
Release: 1%{?dist}
Vendor: SmartWell Inc.
Packager: Fountain Hsiao
URL: http://tengine.taobao.org/
Summary: A distribution of Nginx with some advanced features
License: 2-clause BSD-like license
Group: System Environment/Daemons

Source0: http://tengine.taobao.org/download/tengine-%{version}.tar.gz

BuildRoot: %{_tmppath}/%{software}-%{version}-%{release}-root
BuildRequires: zlib-devel
BuildRequires: openssl-devel
BuildRequires: pcre-devel
%if %rhel == 5
BuildRequires: geoip-devel
%endif
BuildRequires: libxslt-devel
BuildRequires: perl
Requires: initscripts >= 8.36
Requires(pre): shadow-utils
Requires(post): chkconfig
%if %rhel == 5
Requires: geoip
%endif
Requires: libxslt
Provides: webserver

%description
Tengine is a web server originated by Taobao, the largest e-commerce website in Asia. It is based on Nginx HTTP server and has many advanced features. Tengine has been proven very stable and efficient on the top 100 global websites, including taobao.com and tmall.com.

Tengine has been an open source project since December 2011. It is now developed and maintained by the Tengine team, whose core members are from Taobao, Sogou and other Internet companies.

%prep
%setup -q -n %{software}-%{version}

%build
./configure \
    --prefix=%{nginx_home} \
    --conf-path=%{nginx_home}/conf/nginx.conf \
    --user=%{nginx_user} \
    --group=%{nginx_group} \
    --http-client-body-temp-path=%{nginx_home_tmp}/client_body \
    --http-proxy-temp-path=%{nginx_home_tmp}/proxy \
    --http-fastcgi-temp-path=%{nginx_home_tmp}/fastcgi \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-cc-opt="%{optflags} $(pcre-config --cflags)" \
    --with-http_addition_module=shared \
    --with-http_image_filter_module=shared \
    --with-http_sub_module=shared \
    --with-http_flv_module=shared \
    --with-http_slice_module=shared \
    --with-http_mp4_module=shared \
    --with-http_concat_module=shared \
    --with-http_random_index_module=shared \
    --with-http_sysguard_module=shared \
    --with-http_charset_filter_module=shared \
    --with-http_userid_filter_module=shared \
    --with-http_footer_filter_module=shared \
    --with-http_autoindex_module=shared \
    --with-http_map_module=shared \
    --with-http_split_clients_module=shared \
    --with-http_referer_module=shared \
    --with-http_uwsgi_module=shared \
    --with-http_scgi_module=shared \
    --with-http_memcached_module=shared \
    --with-http_limit_conn_module=shared \
    --with-http_limit_req_module=shared \
    --with-http_empty_gif_module=shared \
    --with-http_browser_module=shared \
    --with-http_secure_link_module=shared \
    --with-http_upstream_ip_hash_module=shared \
    --with-http_upstream_least_conn_module=shared \
    --with-http_lua_module \
%if %rhel == 5
    --with-http_geoip_module=shared \
%endif
    --with-http_xslt_module=shared \
        $*
make %{?_smp_mflags}

%install
# remove default stripping
%define __spec_install_port /usr/lib/rpm/brp-compress

%{__rm} -rf $RPM_BUILD_ROOT
%{__make} DESTDIR=$RPM_BUILD_ROOT install

%{__mkdir} -p $RPM_BUILD_ROOT%{nginx_home}/var
%{__mkdir} -p $RPM_BUILD_ROOT%{nginx_home_tmp}

%{__rm} -f $RPM_BUILD_ROOT%{nginx_home}/conf/*.default
%{__rm} -f $RPM_BUILD_ROOT%{nginx_home}/conf/fastcgi.conf
%{__rm} -f $RPM_BUILD_ROOT%{nginx_home}/conf/scgi_params
%{__rm} -f $RPM_BUILD_ROOT%{nginx_home}/conf/uwsgi_params

# install SYSV init stuff
%{__mkdir} -p $RPM_BUILD_ROOT%{_initrddir}

%{__cat} > $RPM_BUILD_ROOT%{_initrddir}/nginx <<EOF
#!/bin/sh
#
# nginx        Startup script for nginx
#
# chkconfig: - 85 15
# processname: nginx
# description: nginx is a HTTP and reverse proxy server
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

# Check that networking is up.
. /etc/sysconfig/network

if [ "$NETWORKING" = "no" ]
then
        exit 0
fi

if [ -f /etc/sysconfig/tengine ]; then
        . /etc/sysconfig/tengine
fi

prog=nginx
nginx=${NGINX-/usr/local/nginx/sbin/nginx}
conffile=${CONFFILE-/usr/local/nginx/conf/nginx.conf}
lockfile=${LOCKFILE-/usr/local/nginx/var/nginx.lock}
pidfile=${PIDFILE-/usr/local/nginx/var/nginx.pid}
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

    configtest || return 6
    echo -n $"Staring new master $prog: "
    killproc -p ${pidfile} ${prog} -USR2
    RETVAL=$?
    echo
    sleep 1
    if [ -f ${oldbinpidfile} -a -f ${pidfile} ]; then
        echo -n $"Graceful shutdown of old $prog: "
        killproc -p ${oldbinpidfile} ${prog} -QUIT
        RETVAL=$?
        echo 
    else
        echo $"Upgrade failed!"
        return 1
    fi
}

configtest() {
    ${nginx} -t -c ${conffile}
    RETVAL=$?
    return $RETVAL
}

# See how we were called.
case "$1" in
  start)
	start
	;;
  stop)
	stop
	;;
  status)
        status -p ${pidfile} ${nginx}
	RETVAL=$?
	;;
  restart)
	stop
	start
	;;
  upgrade)
	upgrade
	;;
  condrestart|try-restart)
	if status -p ${pidfile} ${nginx} >&/dev/null; then
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

EOF

%{__mkdir} -p $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
%{__cat} > $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/%{name} <<EOF
NGINX=%{nginx_home}/sbin/nginx
CONFFILE=%{nginx_home}/conf/nginx.conf
LOCKFILE=%{nginx_home}/var/nginx.lock
PIDFILE=%{nginx_home}/var/nginx.pid
EOF

%{__strip} $RPM_BUILD_ROOT%{nginx_home}/sbin/nginx

# install default html
%{__mkdir} -p $RPM_BUILD_ROOT%{mywebroot}
%{__mv} $RPM_BUILD_ROOT%{nginx_home}/html/*.html $RPM_BUILD_ROOT/%{mywebroot}

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root)

%{nginx_home}/sbin/nginx
%{nginx_home}/sbin/dso_tool

%{_initrddir}/nginx

%dir %{nginx_home}/conf

%config(noreplace) %{nginx_home}/conf/browsers
%config(noreplace) %{nginx_home}/conf/module_stubs
%config(noreplace) %{nginx_home}/conf/nginx.conf
%config(noreplace) %{nginx_home}/conf/mime.types
%config(noreplace) %{nginx_home}/conf/fastcgi_params
%config(noreplace) %{nginx_home}/conf/koi-utf
%config(noreplace) %{nginx_home}/conf/koi-win
%config(noreplace) %{nginx_home}/conf/win-utf

%config(noreplace) %{_sysconfdir}/sysconfig/%{name}

%attr(0755,root,root) %dir %{nginx_home}/var

%{mywebroot}
%attr(0755,root,root) %dir %{mywebroot}
%attr(-,%{nginx_user},%{nginx_group}) %dir %{nginx_home_tmp}
%{nginx_home}/modules

%pre
# Add the "web" user
getent group %{nginx_group} >/dev/null || groupadd -r %{nginx_group}
getent passwd %{nginx_user} >/dev/null || \
    useradd -r -g %{nginx_group} -s /sbin/nologin \
    -d %{nginx_home} -c "web user"  %{nginx_user}
exit 0

%post
# Register the nginx service
if [ $1 -eq 1 ]; then
        /sbin/chkconfig --add nginx
fi

%preun
if [ $1 -eq 0 ]; then
        /sbin/service nginx stop > /dev/null 2>&1
        /sbin/chkconfig --del nginx
fi

%postun
if [ $1 -ge 1 ]; then
        /sbin/service nginx upgrade &>/dev/null || :
fi

%changelog
* Mon Nov 26 2012 SmartWell Inc. (Fountain Hsiao <xiao@smartwell.cn>) - 1.4.2
- initial package
