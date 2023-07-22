#!/usr/bin/env bash

# this script is for developers only.
# dependent on the ngx-build script from the nginx-devel-utils repository:
#   https://github.com/openresty/nginx-devel-utils/blob/master/ngx-build
# the resulting nginx is located at ./work/nginx/sbin/nginx

root=`pwd`
version=${1:-1.4.1}
home=~
force=$2

# the ngx-build script is from https://github.com/agentzh/nginx-devel-utils

            #--add-module=$home/work/nginx_upload_module-2.2.0 \

            #--without-pcre \
            #--without-http_rewrite_module \
            #--without-http_autoindex_module \
            #--with-cc=gcc46 \
            #--with-cc=clang \
            #--without-http_referer_module \
            #--with-http_spdy_module \

add_fake_shm_module="--add-module=$root/t/data/fake-shm-module"

time ngx-build $force $version \
            --with-threads \
            --with-pcre-jit \
            --with-ipv6 \
            --with-cc-opt="-DNGX_LUA_USE_ASSERT -I$PCRE_INC" \
            --with-http_v2_module \
            --with-http_realip_module \
            --add-module=$root/../ndk-nginx-module \
            --add-module=$root/../set-misc-nginx-module \
            --with-ld-opt="-L$PCRE_LIB -Wl,-rpath,$PCRE_LIB:$LIBDRIZZLE_LIB" \
            --without-mail_pop3_module \
            --without-mail_imap_module \
            --with-http_image_filter_module \
            --without-mail_smtp_module \
            --with-stream \
            --without-http_upstream_ip_hash_module \
            --without-http_memcached_module \
            --without-http_auth_basic_module \
            --without-http_userid_module \
            --with-http_auth_request_module \
                --add-module=$root/../echo-nginx-module \
                --add-module=$root/../memc-nginx-module \
                --add-module=$root/../srcache-nginx-module \
                --add-module=$root \
                --add-module=$root/../lua-upstream-nginx-module \
              --add-module=$root/../headers-more-nginx-module \
                --add-module=$root/../drizzle-nginx-module \
                --add-module=$root/../rds-json-nginx-module \
                --add-module=$root/../coolkit-nginx-module \
                --add-module=$root/../redis2-nginx-module \
                --add-module=$root/../stream-lua-nginx-module \
                --add-module=$root/t/data/fake-module \
                $add_fake_shm_module \
                --add-module=$root/t/data/fake-delayed-load-module \
                --with-http_gunzip_module \
                --with-http_dav_module \
          --with-select_module \
          --with-poll_module \
                $opts \
                --with-debug

