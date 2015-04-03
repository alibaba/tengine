#!/bin/bash

# this file is mostly meant to be used by the author himself.

version=${1:-0.8.54}
opts=$2

root=$(cd ${0%/*}/.. && echo $PWD)
mkdir -p $root/{build,work}

cd $root
git submodule update --init

cd $root/build
if [ ! -s nginx-$version.tar.gz ]; then
    wget "http://sysoev.ru/nginx/nginx-$version.tar.gz" -O nginx-$version.tar.gz
fi
tar -xzvf nginx-$version.tar.gz

cd nginx-$version/
if [[ "$BUILD_CLEAN" -eq 1 || ! -f Makefile || "$root/config" -nt Makefile || "$root/util/build.sh" -nt Makefile ]]; then
	./configure --prefix=$root/work \
				--add-module=$root \
				--add-module=$root/deps/ngx_devel_kit \
				$opts \
                                --with-debug
fi

if [ -f $root/work/sbin/nginx ]; then
    rm -f $root/work/sbin/nginx
fi

if [ -f $root/work/logs/nginx.pid ]; then
    kill `cat $root/work/logs/nginx.pid`
fi

make -j2
make install

