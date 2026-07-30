#
# Tengine RPM spec -- shared by RHEL-family (RHEL/CentOS/Rocky/Alma/Anolis/
# Alibaba Cloud Linux/Fedora) and SUSE-family (SLES/openSUSE) targets.
#
# The package installs a `tengine` binary driven by /etc/tengine/tengine.conf,
# so it can be installed side by side with a distro nginx package.
#
# Build:
#     rpmbuild -ba packages/build/rpm/tengine.spec \
#         --define "_sourcedir $PWD/dist"
#
# Useful --define overrides:
#     tengine_version 3.2.0     upstream version (filled in by build.sh)
#     build_ts 20260604232239   release timestamp; defaults to build time
#     dist .el7u2               vendor dist tag, e.g. Alibaba Cloud Linux
#     with_zstd 1               enable ngx_zstd  (needs libzstd-devel)
#     with_lua 1                enable ngx_http_lua_module (needs LuaJIT 2.1)
#     with_geoip 1              enable stream geoip (needs GeoIP-devel)
#

%{!?tengine_version:%global tengine_version 3.2.0}
%{!?build_ts:%global build_ts %(date +%%Y%%m%%d%%H%%M%%S)}

# rpm records the builder's hostname in the BUILDHOST tag and it travels with
# the artifact forever. Pin it so a package built on a shared or internal
# machine does not carry that machine's name to whoever installs it.
# Override with --define "_buildhost ..." if a real hostname is wanted.
%global _buildhost tengine-builder

%bcond_with zstd
%bcond_with lua
%bcond_with geoip

# Not defined on older SUSE releases.
%{!?_unitdir: %global _unitdir /usr/lib/systemd/system}

%global tengine_user    tengine
%global tengine_group   tengine
%global tengine_home    %{_localstatedir}/cache/tengine
%global tengine_datadir %{_datadir}/tengine
%global tengine_confdir %{_sysconfdir}/tengine
%global tengine_logdir  %{_localstatedir}/log/tengine

Name:           tengine
Version:        %{tengine_version}
Release:        %{build_ts}%{?dist}
Summary:        Tengine HTTP and reverse proxy server
License:        BSD-2-Clause
URL:            https://tengine.taobao.org/
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  zlib-devel
%if 0%{?suse_version}
BuildRequires:  libopenssl-devel
BuildRequires:  systemd-rpm-macros
Requires(pre):  shadow
%else
BuildRequires:  openssl-devel
BuildRequires:  systemd
Requires(pre):  shadow-utils
%endif
#
# configure prefers PCRE2 and falls back to PCRE1, so either -devel works.
# Expressing that as a rich dependency lets the solver pick whatever the distro
# actually ships -- important on RHEL 10 (pcre1 dropped) and on derivatives
# such as openEuler / Kylin / UOS that define neither %%rhel nor %%fedora, and
# would otherwise silently fall into the pcre1 branch.
#
# Rich deps need rpm >= 4.13. Guessing that from the distro release is
# unreliable (el7-era derivatives do not all define %%rhel), so build.sh probes
# the running rpm and passes have_rich_deps. Default 0 keeps a bare
# `rpmbuild -ba` working on any rpm version.
#
%{!?have_rich_deps:%global have_rich_deps 0}

%if %{have_rich_deps}
BuildRequires:  (pcre2-devel or pcre-devel)
%else
%if 0%{?rhel} >= 10 || 0%{?fedora} >= 39
BuildRequires:  pcre2-devel
%else
BuildRequires:  pcre-devel
%endif
%endif
%if %{with zstd}
BuildRequires:  libzstd-devel
%endif
%if %{with geoip}
BuildRequires:  GeoIP-devel
%endif

Requires:       logrotate
%{?systemd_requires}

Provides:       webserver

%description
Tengine is a web server originated by Taobao. It is based on the nginx HTTP
server and adds many advanced features such as dynamic module loading,
upstream health checks, session sticky load balancing, request statistics and
consistent hashing.

This package ships the server as /usr/sbin/tengine configured through
/etc/tengine/tengine.conf, which keeps it independent from any nginx package
installed on the same host.

%prep
%setup -q

%build
# The tree defaults to -Werror (auto/cc/gcc); combined with distro hardening
# flags and an arbitrary compiler version that is a guaranteed build break,
# so relax it for packaging.
export TENGINE_LIBDIR="%{_libdir}"
%if %{with zstd}
export TENGINE_WITH_ZSTD=yes
%endif
%if %{with lua}
export TENGINE_WITH_LUA=yes
%endif
%if %{with geoip}
export TENGINE_WITH_GEOIP=yes
%endif

./configure \
    $(sh packages/build/configure-args.sh) \
    --with-cc-opt="%{optflags} -Wno-error" \
    --with-ld-opt="%{?build_ldflags}"

make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}

# make install drops the stock nginx.conf plus *.default copies; replace them
# with the packaged tengine.conf so the shipped names stay consistent.
rm -f %{buildroot}%{tengine_confdir}/*.default
install -p -m 0644 packages/build/conf/tengine.conf \
    %{buildroot}%{tengine_confdir}/tengine.conf
install -d -m 0755 %{buildroot}%{tengine_confdir}/conf.d
install -p -m 0644 packages/build/conf/conf.d/default.conf \
    %{buildroot}%{tengine_confdir}/conf.d/default.conf

install -D -p -m 0644 packages/build/conf/tengine.service \
    %{buildroot}%{_unitdir}/tengine.service
install -D -p -m 0644 packages/build/conf/tengine.logrotate \
    %{buildroot}%{_sysconfdir}/logrotate.d/tengine

# man page, with the packaged paths substituted in
sed -e 's|%%PREFIX%%|%{tengine_datadir}|' \
    -e 's|%%PID_PATH%%|/run/tengine.pid|' \
    -e 's|%%CONF_PATH%%|%{tengine_confdir}/tengine.conf|' \
    -e 's|%%ERROR_LOG_PATH%%|%{tengine_logdir}/error.log|' \
    man/nginx.8 > tengine.8
install -D -p -m 0644 tengine.8 %{buildroot}%{_mandir}/man8/tengine.8

install -d -m 0700 %{buildroot}%{tengine_home}
install -d -m 0755 %{buildroot}%{tengine_logdir}
install -d -m 0755 %{buildroot}%{_libdir}/tengine/modules

# /run is a tmpfs; make install creates it because of --pid-path
rm -rf %{buildroot}/run %{buildroot}%{_localstatedir}/run

%pre
getent group %{tengine_group} >/dev/null || \
    groupadd -r %{tengine_group}
getent passwd %{tengine_user} >/dev/null || \
    useradd -r -g %{tengine_group} -s /sbin/nologin \
        -d %{tengine_home} -c "Tengine web server" %{tengine_user}
%if 0%{?suse_version}
%service_add_pre tengine.service
%endif
exit 0

%post
%if 0%{?suse_version}
%service_add_post tengine.service
%else
%systemd_post tengine.service
%endif

%preun
%if 0%{?suse_version}
%service_del_preun tengine.service
%else
%systemd_preun tengine.service
%endif

%postun
%if 0%{?suse_version}
%service_del_postun tengine.service
%else
%systemd_postun_with_restart tengine.service
%endif

%files
%license LICENSE
%doc README.markdown CHANGES.te AUTHORS.te
%{_sbindir}/tengine
%{_mandir}/man8/tengine.8*
%{_unitdir}/tengine.service
%dir %{_libdir}/tengine
%dir %{_libdir}/tengine/modules
%dir %{tengine_datadir}
%{tengine_datadir}/html
%dir %{tengine_confdir}
%dir %{tengine_confdir}/conf.d
%config(noreplace) %{tengine_confdir}/tengine.conf
%config(noreplace) %{tengine_confdir}/conf.d/default.conf
%config(noreplace) %{tengine_confdir}/mime.types
%config(noreplace) %{tengine_confdir}/fastcgi.conf
%config(noreplace) %{tengine_confdir}/fastcgi_params
%config(noreplace) %{tengine_confdir}/scgi_params
%config(noreplace) %{tengine_confdir}/uwsgi_params
%config(noreplace) %{tengine_confdir}/koi-utf
%config(noreplace) %{tengine_confdir}/koi-win
%config(noreplace) %{tengine_confdir}/win-utf
%config(noreplace) %{_sysconfdir}/logrotate.d/tengine
%attr(0700,%{tengine_user},%{tengine_group}) %dir %{tengine_home}
%attr(0755,%{tengine_user},%{tengine_group}) %dir %{tengine_logdir}

%changelog
* Thu Jul 30 2026 Tengine Team <tengine@taobao.net> - 3.2.0-1
- Initial RPM packaging: tengine binary, tengine.conf, systemd unit.
