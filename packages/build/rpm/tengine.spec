#
# Tengine RPM spec -- shared by RHEL-family (RHEL/CentOS/Rocky/Alma/Anolis/
# Alibaba Cloud Linux/Fedora) and SUSE-family (SLES/openSUSE) targets.
#
# The package installs a `tengine` binary driven by /etc/tengine/tengine.conf,
# so it can be installed side by side with a distro nginx package.
#
# Tongsuo (NTLS), xquic (QUIC/HTTP-3) and the Lua stack are part of the default
# feature set. None of them exist in any distro repository, so Source1 carries
# their pinned sources (see packages/build/deps.env) and %build compiles them
# before Tengine itself. That also means this package links a private,
# statically built Tongsuo instead of the system OpenSSL: a distro OpenSSL
# security update does NOT cover it, the package has to be rebuilt.
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
#     with_geoip 1              enable stream geoip (needs GeoIP-devel)
#
# Opting out of the heavy dependencies (mainly for debugging a build):
#     --without tongsuo         system OpenSSL, no NTLS; implies --without xquic
#     --without xquic           no QUIC/HTTP-3
#     --without lua             no ngx_http_lua_module
#

%{!?tengine_version:%global tengine_version 3.2.0}
%{!?build_ts:%global build_ts %(date +%%Y%%m%%d%%H%%M%%S)}

# rpm records the builder's hostname in the BUILDHOST tag and it travels with
# the artifact forever. Pin it so a package built on a shared or internal
# machine does not carry that machine's name to whoever installs it.
# Override with --define "_buildhost ..." if a real hostname is wanted.
%global _buildhost tengine-builder

%bcond_with zstd
%bcond_with geoip

# A CMake installed outside the package manager (pip, upstream tarball,
# /usr/local) is perfectly usable by build-deps.sh but invisible to rpm, so its
# BuildRequires could never be satisfied. build.sh detects that and enables
# this to drop just the CMake requirement -- everything else stays checked,
# unlike a blanket --nodeps.
%bcond_with external_cmake

# Default feature set: everything Tengine is known for. Turn off with
# --without tongsuo / --without xquic / --without lua.
%bcond_without tongsuo
%bcond_without xquic
%bcond_without lua

# libxquic.so and libluajit live in %%{_libdir}/tengine, private to this
# package. Keep them out of the automatic dependency generator on both sides:
# they must not be advertised as system-wide provides, and nothing (including
# the tengine binary that links them) may end up requiring their sonames from
# the outside.
%global __provides_exclude_from ^%{_libdir}/tengine/.*\\.so.*$
%global __requires_exclude ^(libxquic\\.so.*|libluajit-5\\.1\\.so.*)$

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
# Tengine and the resty Lua libraries are BSD-2-Clause, Tongsuo and xquic are
# Apache-2.0, LuaJIT is MIT.
License:        BSD-2-Clause AND Apache-2.0 AND MIT
URL:            https://tengine.taobao.org/
Source0:        %{name}-%{version}.tar.gz
# Pinned third-party sources (Tongsuo, xquic, LuaJIT, resty Lua libraries),
# assembled by packages/build/build.sh from packages/build/deps.env.
Source1:        %{name}-deps.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  zlib-devel
%if %{with xquic}
# xquic is built with CMake and links against libstdc++.
#
# el7-era distros ship CMake 2.8 as "cmake" and 3.x as "cmake3", so requiring
# "cmake >= 3.5" there can never be satisfied. build-deps.sh already probes
# both binaries (find_cmake), so accept either package and let it pick.
# Rich deps need rpm >= 4.13; see have_rich_deps above.
%if %{without external_cmake}
%if %{have_rich_deps}
BuildRequires:  (cmake >= 3.5 or cmake3 >= 3.5)
%else
%if 0%{?rhel} == 7
BuildRequires:  cmake3 >= 3.5
%else
BuildRequires:  cmake >= 3.5
%endif
%endif
%endif
BuildRequires:  gcc-c++
%endif
%if %{with tongsuo}
# Tongsuo's Configure is Perl and needs FindBin; Text::Template comes from the
# tarball's own external/perl fallback. SUSE and el7 ship one monolithic perl,
# everything newer splits the interpreter and FindBin into separate packages.
%if 0%{?suse_version}
BuildRequires:  perl
%else
%if 0%{?rhel} == 7
BuildRequires:  perl
%else
BuildRequires:  perl-interpreter
BuildRequires:  perl-FindBin
%endif
%endif
%endif
%if 0%{?suse_version}
# Only used when built --without tongsuo; otherwise Tongsuo provides the TLS
# stack and is linked statically.
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
# -a 1 unpacks the dependency tarball into deps/ inside the source tree.
%setup -q -a 1

%build
export TENGINE_LIBDIR="%{_libdir}"
%if %{with zstd}
export TENGINE_WITH_ZSTD=yes
%endif
%if %{with geoip}
export TENGINE_WITH_GEOIP=yes
%endif

# Build the pinned third-party dependencies first. --libdir is the *installed*
# location: ngx_http_xquic_module records it as libxquic.so's runtime path, so
# it must be the final path rather than this build tree.
deps_args=""
%if %{without tongsuo}
export TENGINE_WITH_TONGSUO=no
deps_args="$deps_args --without-tongsuo"
%endif
%if %{without xquic}
export TENGINE_WITH_XQUIC=no
deps_args="$deps_args --without-xquic"
%endif
%if %{without lua}
export TENGINE_WITH_LUA=no
deps_args="$deps_args --without-lua"
%endif

sh packages/build/build-deps.sh \
    --srcdir deps \
    --workdir %{_builddir}/deps-build \
    --staging %{_builddir}/deps-staging \
    --libdir %{_libdir}/tengine \
    --datadir %{tengine_datadir} \
    --env-relative-to "$PWD" \
    $deps_args

# Exports TENGINE_TONGSUO_SRC / TENGINE_XQUIC_* / LUAJIT_INC / LUAJIT_LIB.
. %{_builddir}/deps-build/deps-env.sh

# The tree defaults to -Werror (auto/cc/gcc); combined with distro hardening
# flags and an arbitrary compiler version that is a guaranteed build break,
# so relax it for packaging.
./configure \
    $(sh packages/build/configure-args.sh) \
    --with-cc-opt="%{optflags} -Wno-error" \
    --with-ld-opt="%{?build_ldflags} $(sh packages/build/configure-args.sh --print-ld-opt)" \
    --with-openssl-opt="$(sh packages/build/configure-args.sh --print-openssl-opt)"

make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}

# The bundled libraries (libxquic.so, libluajit) and the Lua modules built by
# build-deps.sh are staged with their final absolute paths already in place.
cp -a %{_builddir}/deps-staging/. %{buildroot}/

# make install drops the stock nginx.conf plus *.default copies; replace them
# with the packaged tengine.conf so the shipped names stay consistent.
rm -f %{buildroot}%{tengine_confdir}/*.default
install -p -m 0644 packages/build/conf/tengine.conf \
    %{buildroot}%{tengine_confdir}/tengine.conf
install -d -m 0755 %{buildroot}%{tengine_confdir}/conf.d
install -p -m 0644 packages/build/conf/conf.d/default.conf \
    %{buildroot}%{tengine_confdir}/conf.d/default.conf

# lua_package_cpath points at the private libdir, which is /usr/lib64 here and
# /usr/lib on deb/apk, so the config ships a placeholder.
sed -i -e 's|@TENGINE_LIBDIR@|%{_libdir}|g' \
    %{buildroot}%{tengine_confdir}/tengine.conf
%if %{without lua}
# Without the Lua module those directives would be unknown at startup.
sed -i -e '/lua_package_/d' %{buildroot}%{tengine_confdir}/tengine.conf
%endif

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
%if %{with xquic}
%{_libdir}/tengine/libxquic.so
%endif
%if %{with lua}
%{_libdir}/tengine/libluajit-5.1.so*
%{_libdir}/tengine/lualib
%{tengine_datadir}/lualib
%endif
%{tengine_datadir}/licenses
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
* Thu Jul 30 2026 Tengine Team <tengine@taobao.net> - 3.2.0-2
- Build Tongsuo (NTLS), xquic (QUIC/HTTP-3) and the Lua stack from pinned
  sources and enable them by default.

* Thu Jul 30 2026 Tengine Team <tengine@taobao.net> - 3.2.0-1
- Initial RPM packaging: tengine binary, tengine.conf, systemd unit.
