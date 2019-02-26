ngx_debug_timer
==============

This module provides access to information of timer usage for nginx/tengine.

Example
=======

Get information of timer usage.
---------------------------------

```
 http {
    server {
        listen 80;

        location = /debug_timer {
            debug_timer;
        }
    }
 }
```

Requesting URI /debug_timer, you will get information of timer usage for nginx/tengine.
The output page may look like as follows:

```
$ curl 'localhost:80/debug_timer'
pid:80490
timer:2
--------- [0] --------
timers[i]: 00007F837D02C4B8
    timer: 148
       ev: 00007F837D02C488
     data: 00007F837D02C450
  handler: 000000010778B450
   action:
--------- [1] --------
timers[i]: 00007F837D02C698
    timer: 1263
       ev: 00007F837D02C668
     data: 00007F837D02C630
  handler: 000000010778B450
   action:
```

Get information of timer usage
-----------------------------------

Data
====

Every block like "[0]" except the related timer usage as follows:

* __timers__: address of current timer
* __timer__: timeout of current timer
* __ev__: related event of current timer
* __data__: related event data of current timer
* __handler__: related event handler of current timer, use addr2line to find the real function
* __action__: log action of current timer

Nginx Compatibility
===================

The latest module is compatible with the following versions of nginx:

* 1.13.4 (stable version of 1.13.x) and later

Tengine Compatibility
=====================

* 2.1.1 (stable version of 2.1.x) and later

Install
=======

Install this module from source:

```
$ wget http://nginx.org/download/nginx-1.13.4.tar.gz
$ tar -xzvf nginx-1.13.4.tar.gz
$ cd nginx-1.13.4/
$ ./configure --add-module=/path/to/ngx_debug_timer
$ make -j4 && make install
```

Directive
=========

Syntax: **debug_timer**

Default: `none`

Context: `server, location`

The information of nginx timer usage will be accessible from the surrounding location.

Exception
=========
