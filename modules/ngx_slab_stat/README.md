ngx_slab_stat
==============

This module provides access to information of slab usage for nginx/tengine shared memory.

Example
=======

Get information of slab and free page usage.
---------------------------------

```
 http {
    server {
        listen 80;

        location = /slab_stat {
            slab_stat;
        }
    }
 }
```

Requesting URI /slab_stat, you will get information of slab and free page usage for nginx/tengine shared memory.
The output page may look like as follows:

```
$ curl http://localhost:80/slab_stat
* shared memory: one
total:      102400(KB) free:      101792(KB) size:           4(KB)
pages:      101792(KB) start:0000000003496000 end:0000000009800000
slot:           8(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:          16(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:          32(Bytes) total:         127 used:           1 reqs:           1 fails:           0
slot:          64(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:         128(Bytes) total:          32 used:           1 reqs:           1 fails:           0
slot:         256(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:         512(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:        1024(Bytes) total:           0 used:           0 reqs:           0 fails:           0
slot:        2048(Bytes) total:           0 used:           0 reqs:           0 fails:           0
```

Get information of shared memory usage
-----------------------------------

Data
====

Every line except the first three of output content has the same format, as follows:

* __shared memory__: name of current shared memory zone

* __total__: total size of current shared memory zone
* __free__: free size of current shared memory zone now
* __size__: page size of current shared memory zone

* __pages__: continuous page size that can be allocated
* __start__: start address of current continuous page size
* __end__: end address of current continuous page size

* __slot__: slot that can be allocated
* __total__: total number of current slot
* __used__: used number of current slot
* __reqs__: reqs number of current slot
* __fails__: fails number of current slot

Nginx Compatibility
===================

The latest module is compatible with the following versions of nginx:

* 1.13.4 (stable version of 1.13.x)

Nginx cores older than 1.13.x should be patched (refer "Install").

Tengine Compatibility
=====================

* 2.1.1 (stable version of 2.1.x)

Tengine version older than 2.1.x should be patched (refer "Install").

Install
=======

Install this module from source:

```
$ wget http://nginx.org/download/nginx-1.13.4.tar.gz
$ tar -xzvf nginx-1.13.4.tar.gz
$ cd nginx-1.13.4/
$ ./configure --add-module=/path/to/ngx_slab_stat
$ make -j4 && make install
```

Note that `slab_stat.patch` should be applied when nginx cores older than 1.13.x, you can also generate this patch by diff with nginx 1.13.x.

```
$ patch -p1 < /path/to/ngx_slab_stat/slab_stat.patch
```

Directive
=========

Syntax: **slab_stat**

Default: `none`

Context: `server, location`

The information of nginx shared memory usage will be accessible from the surrounding location.

Exception
=========

Now only support shared memory allocated from nginx and [lua-nginx-module](https://github.com/openresty/lua-nginx-module)
