Name
====

ngx_http_copy_module

Description
===========

This module can copy realtime http requests to specified destination, and orignal request will not be affected.<br>
It will recevie all the responses of copied requests and drop them.

With this module, we can copy online traffic to anywhere for testing or analysis.

This module can only be worked with Tengine, it uses Tengine input body filter to copy request body.<br>
(This module for standard nginx is available here: [ngx_http_copy_module](http://github.com/chobits/ngx_http_copy_module).)

If HTTPS/SPDY is enabled on frontend, only plain http request, converted from HTTPS/SPDY traffic, will be copied.


Compilation
===========

The module is not compiled into Tengine by default.<br>
It can be enabled with '--with-http_copy_module' configuration parameter,<br>
or it can be compiled as a '.so' with '--with-http_copy_module=shared'.


Example
=======

```
http {

    server {
        listen 80;

        # copy requests to these two test machines
        http_copy 127.0.0.1:7001;
        http_copy 127.0.0.1:7002 multiple=2;    # 1 incoming request with 2 copies

        location / {
            proxy_pass http://backend;
        }

        location = /http_copy_status {
            # dont copy request to "/http_copy_status"
            http_copy off;
            http_copy_status;
        }
    }
}
```

With this config, incoming requests will be proxied to backend.<br>
And also they will be copied to test machines (127.0.0.1:7001 & :7002) as following:

```
client --> (Tengine) --> (backend)
                  ‖ |
                  ‖ '--> (127.0.0.1:7001)
                  ‖
                  `====> (127.0.0.1:7002)
```

Directives
==========

http_copy
---------

**Syntax**:
* http_copy address [multiple=\<n>] [connections=\<n>] [switch_on=$nginx_variable] [fail_timeout=\<time>] [max_fails=\<n>] [serial];
* http_copy off;

**Default**: none

**Context**: main, server, location, if

**Example**: `http_copy 127.0.0.1:7001 mutiple=4 connections=512 switch_on=$is_http_get fail_timeout=10s max_fails=1 serial;`

Defines the address and other parameters of a server.<br>
The address can be specified as a domain name or IP address, with an optional port.<br>
If a port is not specified, the port 80 is used.

**Parameters**:
* `mutilple`:
   set the multiple of copied request. (1x by default)
* `connections`:
   set the maximum number of connections for copied requests.<br>
   (unlimited (65535) by default)
*  `max_fails`:
   set the maximum number of continuous failures to communicate with the server. (5 by default)<br>
   If reaching the limit (**>= max_fails**), it marks the server as unavailable for a duration set by the fail_timeout parameter. <br>
   The zero value disables the accounting of failures.
*  `fail_timeout`:
   set the period of time the server will be considered unavailable. (10s by default)<br>
   After this time, it tries copying requests to the server again.
* `serial`:
   set multiple copies of one incoming request in single connection (like http pipelining).<br>
   If copied multiple is very large, this option can limit number of concurrent connections effectly.
* `switch_on`:
   set the switch variable, which determines whether enables http_copy.<br>
   If the value of switch variable is "true", http_copy will be enabled.

```
# example for copying GET requests only

http_copy 127.0.0.1:7001 switch_on=$is_http_get;

set $is_http_get "false";

if ($request_method = "GET") {
  set $is_http_get "true";
}

location / {
    proxy_pass http://backend;
}
```

http_copy_keepalive
-------------------

**Syntax**:
* http_copy_keepalive [max_cached=\<n>] [timeout=\<n>] [force_off];
* http_copy_keepalive off;

**Default**: http_copy_keepalive max_cached=65535 timeout=60000;

**Context**: main, server, location, if

**Parameters**:
* `max_cached`:
  set the maximum number of cached connections for copied requests.
* `timeout`:
  set a timeout of cached connection. The unit of this value is millisecond.<br>
  If the cached connection is not used within this time, it will be closed.
* `force_off`:
  The version of copied request is set to "HTTP/1.1" and "Connection:" header is removed by default.<br>
  If force_off is set, the above behavior will be avoided.

http_copy_unparsed_uri
----------------------

**Syntax**: http_copy_unparsed_uri on|off;

**Default**: http_copy_unparsed_uri on;

**Context**: main, server, location

Determine whether the copied uri is unparsed uri ($request_uri) or overwritten uri ($uri).<br>
If enabled, the uri of copied request is the uri of original request ($request_uri).

```
# example for copying overwritten uri
# Incoming request of uri "/acbd18.jpg" is copied to 127.0.0.1:7001 with uri "/jpg/acbd18".

server {
   http_copy 127.0.0.1:7001;
   http_copy_unparsed_uri off;

   rewrite (.*)\.jpg /jpg/$1 break;    # overwrite uri from /XXX.jpg to /jpg/XXX

   location /jpg/ {
       proxy_pass http://image_server;
   }
}
```

http_copy_status
----------------

**Syntax**: http_copy_unparsed_uri;

**Default**: none

**Context**: location

The status information of copied requests will be accessible from the surrounding location.

```
# example for status information
$ curl http://127.0.0.1:80/http_copy_status
+ long time:
Request: 92298
Response: 91283
Response(OK): 91283
Response(ERROR): 0
Connect: 3254
Connect(keepalive): 89044
read: 43144466432 bytes
read(chunk): 43144466432 bytes
write: 0 bytes

+ real time:
Connect: 1016
Connect(keepalive): 1016
```

The following status information is provided:
- **long time**:
 - **Request**: the total number of copied requests
 - **Response**: the total number of responses for copied requests
 - **Response(OK)**: the total number of 2XX, 3XX responses
 - **Response(ERROR)**: the total number of 4XX, 5XX and other responses
 - **Connect**: the total number of created connections
 - **Connect(keepalive)**: the total number of connections reusing
 - **read**: the total number of bytes received from backends 
 - **read(chunk)**: the total number of bytes received from backends for chunked-encoding responses
 - **write**: unimplemented, always 0
- **real time**:
 - **Connect**: the total number of active backend connections
 - **Connect(keepalive)**: the total number of active reused connections
