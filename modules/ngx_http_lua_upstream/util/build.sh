#!/bin/bash

# this file is mostly meant to be used by the author himself.

#set -x

root=`pwd`
version=$1
home=~
force=$2

ngx_redis_version=0.3.9
cd $home/work/nginx/ || exit 1
ngx_redis_path=$home/work/nginx/ngx_http_redis-$ngx_redis_version
rm -rf $ngx_redis_path || exit 1
tar -xzvf ngx_http_redis-$ngx_redis_version.tar.gz || exit 1

cd $ngx_redis_path || exit 1

patch_file=$root/../openresty/patches/ngx_http_redis-$ngx_redis_version-variables_in_redis_pass.patch
if [ ! -f $patch_file ]; then
    echo "$patch_file: No such file" > /dev/stderr
    exit 1
fi
# we ignore any errors here since the target directory might have already been patched.
patch -p1 < $patch_file || exit 1

cd $ngx_redis_path || exit 1

patch_file=$root/../openresty/patches/ngx_http_redis-$ngx_redis_version-default_port_fix.patch
if [ ! -f $patch_file ]; then
    echo "$patch_file: No such file" > /dev/stderr
    exit 1
fi
# we ignore any errors here since the target directory might have already been patched.
patch -p1 < $patch_file || exit 1

disable_pcre2="";
patch_file=$root/../openresty/patches/ngx_http_redis-$ngx_redis_version-remove_content_encoding.patch
answer=`$root/../openresty/util/ver-ge "$version" 1.23.0`
if [ "$answer" = "Y" ]; then
    disable_pcre2=--without-pcre2;
    echo
    echo "applying ngx_http_redis-$ver-remove_content_encoding.patch"
    patch -p1 < $patch_file || exit 1
    echo
fi

cd $root || exit 1

            #--without-http_memcached_module \
ngx-build $force $version \
            $disable_pcre2 \
            --with-cc-opt="-O0" \
            --with-ld-opt="-Wl,-rpath,/opt/postgres/lib:/opt/drizzle/lib:/usr/local/lib" \
            --without-mail_pop3_module \
            --without-mail_imap_module \
            --without-mail_smtp_module \
            --without-http_upstream_ip_hash_module \
            --without-http_empty_gif_module \
            --without-http_referer_module \
            --without-http_autoindex_module \
            --without-http_auth_basic_module \
            --without-http_userid_module \
            --add-module=$root/../ndk-nginx-module \
            --add-module=$root/../set-misc-nginx-module \
          --add-module=$ngx_redis_path \
          --add-module=$root/../echo-nginx-module \
          --add-module=$root $opts \
          --add-module=$root/../lua-nginx-module \
          --with-select_module \
          --with-poll_module \
          --with-debug
          #--add-module=/home/agentz/git/dodo/utils/dodo-hook \
          #--add-module=$home/work/ngx_http_auth_request-0.1 #\
          #--with-rtsig_module
          #--with-cc-opt="-g3 -O0"
          #--add-module=$root/../echo-nginx-module \
  #--without-http_ssi_module  # we cannot disable ssi because echo_location_async depends on it (i dunno why?!)

