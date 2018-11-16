ngx_debug_conn
==============

This module provides access to information of connection usage for nginx/tengine.

Example
=======

Get information of connection usage.
---------------------------------

```
 http {
    server {
        listen 80;

        location = /debug_conn {
            debug_conn;
        }
    }
 }
```

Requesting URI /debug_conn, you will get information of connection usage for nginx/tengine.
The output page may look like as follows:

```
$ curl 'localhost:80/debug_conn'
pid:70568
connections:3
--------- [1] --------
conns[i]: 0
      fd: 6
    addr: 0.0.0.0:80
    sent: 0
  action: (null: listening)
 handler: r:000000010DAEBEC0 w:0000000000000000
requests: 0
poolsize: 0
--------- [2] --------
conns[i]: 1
      fd: 7
    addr: (null)
    sent: 0
  action: (null: channel)
 handler: r:000000010DAFB770 w:0000000000000000
requests: 0
poolsize: 0
--------- [3] --------
conns[i]: 2
      fd: 3
    addr: 127.0.0.1
    sent: 0
  action: (null)
 handler: r:000000010DB28CA0 w:000000010DB28CA0
requests: 1
poolsize: 0
********* request ******
     uri: http://localhost/debug_conn
 handler: r:000000010DB26820 w:000000010DB29770
startsec: 1542356262
poolsize: 0
```

Get information of connection usage
-----------------------------------

Data
====

Every block like "[1]" except the related connection usage as follows:

* __conns__: sequence of current connection
* __fd__: file description of current connection
* __addr__: listening address of current connection
* __sent__: data sent size of current connection
* __action__: log action of current connection
* __handler__: read/write event handler of current connection, use addr2line to find the real function
* __requests__: request numbers of current connection
* __poolsize__: memory pool size of current connection
* __request__: request of current connection
* __uri__: request uri of current connection
* __handler__: read/write event handler of the request, use addr2line to find the real function
* __startsec__: start timestamp of the request
* __poolsize__: memory pool size of the request

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
$ ./configure --add-module=/path/to/ngx_debug_conn
$ make -j4 && make install
```

Directive
=========

Syntax: **debug_conn**

Default: `none`

Context: `server, location`

The information of nginx connection usage will be accessible from the surrounding location.

Exception
=========

```
********* request ******
```

The request block will only show when request exists in connection.
