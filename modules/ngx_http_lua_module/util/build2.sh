#!/usr/bin/env bash

# this file is mostly meant to be used by the author himself.

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

time ngx-build $force $version \
            --with-cc-opt="-I$PCRE_INC" \
            --with-http_realip_module \
        --with-http_ssl_module \
            --add-module=$root/../ndk-nginx-module \
            --add-module=$root/../set-misc-nginx-module \
            --with-ld-opt="-L$PCRE_LIB -Wl,-rpath,$PCRE_LIB:$LIBDRIZZLE_LIB:/usr/local/lib" \
            --with-http_spdy_module \
            --without-mail_pop3_module \
            --without-mail_imap_module \
            --without-mail_smtp_module \
            --without-http_upstream_ip_hash_module \
            --without-http_empty_gif_module \
            --without-http_memcached_module \
            --without-http_auth_basic_module \
            --without-http_userid_module \
                --add-module=$home/work/nginx/ngx_http_auth_request_module-0.2 \
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
                --with-http_gunzip_module \
          --with-select_module \
          --with-poll_module \
          --with-rtsig_module \
                $opts \
                --with-debug

