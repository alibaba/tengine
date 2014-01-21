%global  tengine_user          nobody
%global  tengine_group         %{tengine_user}
%global  tengine_home          /var/log/tengine
%global  tengine_home_tmp      %{tengine_home}/tmp
%global  tengine_logdir        %{tengine_home}
%global  tengine_confdir       %{_sysconfdir}/tengine
%global  tengine_datadir       %{_datadir}/tengine
%global  tengine_webroot       %{tengine_datadir}/html

Name:              tengine
Version:           1.5.2
Release:           3%{?dist}

Summary:           A high performance web server and reverse proxy server
Group:             System Environment/Daemons
License:           BSD
URL:               http://tengine.taobao.org

%define _sourcedir %_topdir/SOURCES
Source0:           %{name}-%{version}.tar.gz
Source1:           tengine.init
Source2:           tengine.logrotate
Source3:           tengine.conf
Source4:           default.conf
Source5:           ssl.conf
Source6:           virtual.conf
Source7:           tengine.sysconfig
Source8:           module_stubs
Source100:         index.html
Source102:         favicon.ico
Source103:         404.html
Source104:         50x.html
# https://github.com/magicbear/ngx_realtime_request_module
Source105:	   ngx_realtime_request_module-master.zip

# removes -Werror in upstream build scripts.  -Werror conflicts with
# -D_FORTIFY_SOURCE=2 causing warnings to turn into errors.
Patch1:     tengine-mime-types.patch
Patch2:     tengine-http-parse.patch

NoSource:0
NoSource:105
#BuildRequires:     GeoIP-devel
#BuildRequires:     gd-devel
#BuildRequires:     libxslt-devel
BuildRequires:     openssl-devel
BuildRequires:     pcre-devel
BuildRequires:     perl-devel
BuildRequires:     perl(ExtUtils::Embed)
BuildRequires:     zlib-devel
BuildRequires:     jemalloc-devel
Requires:          openssl
Requires:          pcre
Requires:          perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires(pre):     shadow-utils
Requires(post):    chkconfig
Requires(preun):   chkconfig, initscripts
Requires(postun):  initscripts
Provides:          webserver

%description
Tengine is a web server and a reverse proxy server for HTTP, SMTP, POP3 and
IMAP protocols, with a strong focus on high concurrency, performance and low
memory usage.


%prep
%setup -q
%patch1 -p1
unzip %{SOURCE105}
# %patch2 -p1


%build
# tengine does not utilize a standard configure script.  It has its own
# and the standard configure options cause the tengine configure script
# to error out.  This is is also the reason for the DESTDIR environment
# variable.
export DESTDIR=%{buildroot}
./configure \
    --prefix=%{tengine_datadir} \
    --sbin-path=%{_sbindir}/tengine \
    --conf-path=%{tengine_confdir}/tengine.conf \
    --error-log-path=%{tengine_logdir}/error.log \
    --http-log-path=%{tengine_logdir}/access.log \
    --http-client-body-temp-path=%{tengine_home_tmp}/client_body \
    --http-proxy-temp-path=%{tengine_home_tmp}/proxy \
    --http-fastcgi-temp-path=%{tengine_home_tmp}/fastcgi \
    --http-uwsgi-temp-path=%{tengine_home_tmp}/uwsgi \
    --http-scgi-temp-path=%{tengine_home_tmp}/scgi \
    --pid-path=%{_localstatedir}/run/tengine.pid \
    --lock-path=%{_localstatedir}/lock/subsys/tengine \
    --user=%{tengine_user} \
    --group=%{tengine_group} \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-jemalloc \
    --with-http_realip_module \
    --with-http_sysguard_module \
    --add-module=ngx_realtime_request_module-master \
    --with-cc-opt="%{optflags} $(pcre-config --cflags)" \
    --with-ld-opt="-Wl,-E" # so the perl module finds its symbols

make %{?_smp_mflags} 

%install
mkdir -pv %{buildroot}%{tengine_home_tmp} %{buildroot}%{tengine_confdir}/vhost.d
make install DESTDIR=%{buildroot} INSTALLDIRS=vendor

find %{buildroot} -type f -name .packlist -exec rm -f '{}' \;
find %{buildroot} -type f -name perllocal.pod -exec rm -f '{}' \;
find %{buildroot} -type f -empty -exec rm -f '{}' \;
find %{buildroot} -type f -iname '*.so' -exec chmod 0755 '{}' \;

install -p -D -m 0755 %{SOURCE1} \
    %{buildroot}%{_initrddir}/tengine
install -p -D -m 0644 %{SOURCE2} \
    %{buildroot}%{_sysconfdir}/logrotate.d/tengine
install -p -D -m 0644 %{SOURCE7} \
    %{buildroot}%{_sysconfdir}/sysconfig/tengine

install -p -d -m 0755 %{buildroot}%{tengine_confdir}/conf.d
install -p -d -m 0755 %{buildroot}%{tengine_confdir}/vhost.d
install -p -d -m 0755 %{buildroot}%{tengine_home_tmp}
install -p -d -m 0755 %{buildroot}%{tengine_logdir}
install -p -d -m 0755 %{buildroot}%{tengine_webroot}

install -p -m 0644 %{SOURCE3} %{SOURCE8} \
    %{buildroot}%{tengine_confdir}
install -p -m 0644 %{SOURCE4} %{SOURCE5} %{SOURCE6} \
    %{buildroot}%{tengine_confdir}/vhost.d
install -p -m 0644 %{SOURCE100} \
    %{buildroot}%{tengine_webroot}
install -p -m 0644 %{SOURCE102} \
    %{buildroot}%{tengine_webroot}
install -p -m 0644 %{SOURCE103} %{SOURCE104} \
    %{buildroot}%{tengine_webroot}

#install -p -D -m 0644 %{_builddir}/tengine-%{version}/man/tengine.8 \
#    %{buildroot}%{_mandir}/man8/tengine.8

%pre
#if [ $1 -eq 1 ]; then
#    getent group %{tengine_group} > /dev/null || groupadd -r %{tengine_group}
#    getent passwd %{tengine_user} > /dev/null || \
#        useradd -r -d %{tengine_home} -g %{tengine_group} \
#        -s /sbin/nologin -c "Tengine web server" %{tengine_user}
#    exit 0
#fi

%post
if [ $1 == 1 ]; then
    /sbin/chkconfig --add %{name}
fi

%preun
if [ $1 = 0 ]; then
    /sbin/service %{name} stop >/dev/null 2>&1
    /sbin/chkconfig --del %{name}
fi

%postun
if [ $1 == 2 ]; then
    /sbin/service %{name} upgrade || :
fi

%files
%doc LICENSE CHANGES README
%{tengine_datadir}/
%{_sbindir}/tengine
#%{_mandir}/man3/tengine.3pm*
#%{_mandir}/man8/tengine.8*
%{_initrddir}/tengine
%dir %{tengine_confdir}
%dir %{tengine_confdir}/conf.d
%dir %{tengine_confdir}/vhost.d
%dir %{tengine_logdir}
%dir %{tengine_home_tmp}
%config(noreplace) %{tengine_confdir}/browsers
%config(noreplace) %{tengine_confdir}/fastcgi.conf
%config(noreplace) %{tengine_confdir}/fastcgi.conf.default
%config(noreplace) %{tengine_confdir}/fastcgi_params
%config(noreplace) %{tengine_confdir}/fastcgi_params.default
%config(noreplace) %{tengine_confdir}/koi-utf
%config(noreplace) %{tengine_confdir}/koi-win
%config(noreplace) %{tengine_confdir}/mime.types
%config(noreplace) %{tengine_confdir}/module_stubs
%config(noreplace) %{tengine_confdir}/mime.types.default
%config(noreplace) %{tengine_confdir}/tengine.conf
%config(noreplace) %{tengine_confdir}/nginx.conf.default
%config(noreplace) %{tengine_confdir}/scgi_params
%config(noreplace) %{tengine_confdir}/scgi_params.default
%config(noreplace) %{tengine_confdir}/uwsgi_params
%config(noreplace) %{tengine_confdir}/uwsgi_params.default
%config(noreplace) %{tengine_confdir}/win-utf
%config(noreplace) %{tengine_confdir}/vhost.d/*.conf
%config(noreplace) %{_sysconfdir}/logrotate.d/tengine
%config(noreplace) %{_sysconfdir}/sysconfig/tengine
#%dir %{perl_vendorarch}/auto/tengine
#%{perl_vendorarch}/tengine.pm
#%{perl_vendorarch}/auto/tengine/tengine.so
#%attr(-,%{tengine_user},%{tengine_group}) %dir %{tengine_home}
#%attr(-,%{tengine_user},%{tengine_group}) %dir %{tengine_home_tmp}


%changelog
* Mon Jan 20 2014 @ 15:29:14 # hukai
- 增加隐藏文件、目录的过滤，比如 .bash_history 
- 增加vhost监控模块 https://github.com/magicbear/ngx_realtime_request_module
- 将vhost配置文件放入vhost.d目录，其它配置放在conf.d。

* Mon Jan  6 2014 @ 13:00:15 # hukai
- 添加 http_realip_module 、http_sysguard_module 模块

* Wed Nov 20 2013 @ 17:50:02 # hukai
- 打上安全补丁，并升级最新版本 ： http://nginx.org/download/patch.2013.space.txt

* Mon May 20 2013 @ 15:11:24 # hukai
- 默认重定向到毒霸网址导航
- Mime增加Json类型

* Wed May 15 2013 @ 16:52:33  # luhuiyong
- 升级到tengine-1.4.6

* Wed Apr 03 2013 @ 11:07:52  # luhuiyong
- 加入DSO动态加载模块的支持

* Thu Dec 06 2012 @ 14:05:28 # hukai
- Tengine 第1版本，从Nginx直接转换过来
