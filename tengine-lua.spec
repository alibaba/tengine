%global  tengine_datadir       %{_datadir}/tengine
%global  tengine_confdir       %{_sysconfdir}/tengine

Summary:    tengine lua module
Name:       tengine-lua
Version:    1.4.4
Release:    2%{?dist}
Source:     tengine-lua-1.4.4.tar.gz
License:    GPL
Packager:   luhuiyong
Group:      Application
URL:        http://tengine.taobao.org

%define _sourcedir %_topdir/SOURCES
Source1:           lua-module.ini
Source2:           test_lua.conf

Requires:          tengine

%description
This is a tengine lua module

%prep
%setup -q

%build
export DESTDIR=%{buildroot}
./configure \
--with-http_lua_module=shared
make

%install
make dso_install
mkdir -p %{buildroot}%{tengine_datadir}/modules/ %{buildroot}%{tengine_confdir}/conf.d
install -p -D -m 0755 objs/modules/ngx_http_lua_module.so \
    %{buildroot}%{tengine_datadir}/modules/

install -p -D -m 0644  %{SOURCE1} %{SOURCE2}\
  %{buildroot}%{tengine_confdir}/conf.d

%Files
%config(noreplace) %{tengine_confdir}/conf.d/lua-module.ini
%config(noreplace) %{tengine_confdir}/conf.d/test_lua.conf
%{tengine_datadir}/modules/ngx_http_lua_module.so
