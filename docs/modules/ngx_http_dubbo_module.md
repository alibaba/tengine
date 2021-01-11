ngx_http_dubbo_module
====

This module provides support for the backend Dubbo support after Tengine version 2.3.2.
[Apache Dubbo™](http://dubbo.apache.org)  is a high-performance, java based open source RPC framework.It is open source by Alibaba, in years of development, it is one of the most popular microservice framework.

There are two roles Consumer(client) and Provider(Server) in Dubbo. This module is used to make Tengine as a proxy gateway which receives HTTP/HTTPS/HTTP2 requests at the front then as a Dubbo Consumer passes the requests to backend Dubbo Provider service.




```
  User                 tengine (dubbo_pass)                         Dubbo Service Provider
    |                          |                                              |
    |--- GET github.com:443 -->|                                              |
    |                          |--- Dubbo Multiplexing Binary RPC Request  -->|
    |                          |                                              |
    |                          |<-- Dubbo Multiplexing Binary RPC Response ---|
    |<--    HTTP/1.1 200    ---|                                              |
```

Example
=======

Tengine Configuration Example
---------------------

```
upstream dubbo_backend {
    multi 1;
    server 127.0.0.1:20880;
}

server {
    listen 8080;
    
    location / {
        dubbo_pass org.apache.dubbo.demo.DemoService 0.0.0 http_dubbo_tengine dubbo_backend;
    }
}

```

Dubbo Demo Service Example
----------------
### Standard

Dubbo Provider need implement this interface, then configure the service name, Service version and service method to ```dubbo_pass``` like this. Tengine will convert HTTP/HTTPS/HTTP2 request to Dubbo interface invoke.

```
Map<String, Object> dubbo_method(Map<String, Object> context);

```

Input param ```Map<String, Object> context``` with a number of key and value， you can use ```dubbo_pass_set```,```dubbo_pass_all_headers```,```dubbo_pass_body``` directives to div them, last key is the retained field:
```
body: HTTP request Body, value Object type is byte[]

```

For output param ```Map<String, Object> context```, last key is the retained field:
```
body: HTTP response Body, value Object type is byte[]
statue: HTTP response Status, value type is String
```



### Extend(Stay tuned for updates)

Support configure param mapping on Tengine, support invoke any Dubbo Provider method not need any change (Stay tuned for updates).


QuickStart
=======
This is a [QuickStart for Tengine Dubbo](https://github.com/apache/dubbo-samples/tree/master/dubbo-samples-tengine)


Install
=======

Build Tengine with this module from source:

```
$ ./configure --add-module=./modules/mod_dubbo --add-module=./modules/ngx_multi_upstream_module --add-module=./modules/mod_config
$ make && make install
```

Dynamic module support

* mod_dubbo: ```support``` build as a dynamic module
* ngx_multi_upstream_module: ```no support``` build as a dynamic module
* mod_config: ```support but no need``` build as a dynamic module


Directive
=========

dubbo_pass
-------------
Syntax: **dubbo_pass** *service_name* *service_version* *method* *upstream_name*  
Default: `none`  
Context: `location, if in location` 

configure use Dubbo protocol proxy to upstream

*service_name*: Dubbo provider service name
*service_version*: Dubbo provider service version
*method*: Dubbo provider service method
*upstream_name*: backend upstream name

Nginx variables can be used as `service_name`, `service_version` and `method`.

```
# proxy to upstream dubbo_backend
upstream dubbo_backend {
    multi 1;
    server 127.0.0.1:20880;
}

set $dubbo_service_name "org.apache.dubbo.demo.DemoService";
set $dubbo_service_name "0.0.0";
set $dubbo_service_name "http_dubbo_nginx";

dubbo_pass $dubbo_service_name $dubbo_service_version $dubbo_method dubbo_backend;
```

Notice:

`dubbo_pass` only support multi upstream, must use `multi` configure in upstream, multi param is number of multiplexing connection.


dubbo_pass_set
-------------------

Syntax: **dubbo_pass_set** *key* *value*;
Default: `none`
Context: `location, if in location`

When proxy request to backend, need pass this key-value, key and value can contain variables.

```
dubbo_pass_set username $cookie_user;
```

dubbo_pass_all_headers
-----------------------------

Syntax: **dubbo_pass_all_headers** on | off;
Default: `off`
Context: `location, if in location`

Enables or disables passing all http header to backend as key-value.

dubbo_pass_body
--------------------------

Syntax: **dubbo_pass_body** on | off;
Default: `on`
Context: `location, if in location`

Enables or disables passing request body to backend.

dubbo_heartbeat_interval
--------------------------

Syntax: **dubbo_heartbeat_interval** *time*;
Default: `60s`
Context: `http, server, location`

Defines a interval for auto sending ping frame to backend.


dubbo_bind
--------------------------

Syntax:	  **dubbo_bind**  *address* [transparent ] | off;
Default: `off`
Context: `http, server, location`

Like ```proxy_bind```. makes outgoing connections to a Dubbo provider originate from the specified local IP address with an optional port. Parameter value can contain variables. The special value off cancels the effect of the dubbo_bind directive inherited from the previous configuration level, which allows the system to auto-assign the local IP address and port.

The transparent parameter allows outgoing connections to a Dubbo provider originate from a non-local IP address, for example, from a real IP address of a client:
```
dubbo_bind $remote_addr transparent;
```
In order for this parameter to work, it is usually necessary to run nginx worker processes with the superuser privileges. On Linux it is not required as if the transparent parameter is specified, worker processes inherit the CAP_NET_RAW capability from the master process. It is also necessary to configure kernel routing table to intercept network traffic from the Dubbo provider.



dubbo_socket_keepalive
--------------------------

Syntax:	  **dubbo_socket_keepalive**  on | off;
Default: `off`
Context: `http, server, location`

Like ```proxy_socket_keepalive```, configures the "TCP keepalive" behavior for outgoing connections to a Dubbo provider. By default, the operating system's settings are in effect for the socket. If the directive is set to the value "on", the SO_KEEPALIVE socket option is turned on for the socket.

dubbo_connect_timeout
--------------------------

Syntax:	  **dubbo_connect_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

Like ```proxy_connect_timeout```, defines a timeout for establishing a connection with a Dubbo provider. It should be noted that this timeout cannot usually exceed 75 seconds.

dubbo_send_timeout
--------------------------

Syntax:	  **dubbo_send_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

Like ```proxy_send_timeout```, sets a timeout for transmitting a request to the Dubbo provider. The timeout is set only between two successive write operations, not for the transmission of the whole request. If the Dubbo provider does not receive anything within this time, the connection is closed.


dubbo_read_timeout
--------------------------

Syntax:	  **dubbo_read_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

Like ```proxy_read_timeout```, defines a timeout for reading a response from the Dubbo provider. The timeout is set only between two successive read operations, not for the transmission of the whole response. If the Dubbo provider does not transmit anything within this time, the connection is closed.


dubbo_intercept_errors
--------------------------

Syntax:	  **dubbo_intercept_errors**  on | off;
Default: `off`
Context: `http, server, location`

Like ```proxy_intercept_errors```, determines whether Dubbo provider responses with codes greater than or equal to 300 should be passed to a client or be intercepted and redirected to nginx for processing with the `error_page` directive.


dubbo_buffer_size
--------------------------

Syntax:	  **dubbo_buffer_size**  *size*;
Default: `4k|8k`
Context: `http, server, location`

Like ```proxy_buffer_size```, sets the size of the buffer used for reading the response received from the Dubbo provider. The response is passed to the client synchronously, as soon as it is received.


dubbo_next_upstream
--------------------------

Syntax:	  **dubbo_next_upstream**  error | timeout | invalid_header | http_500 | http_502 | http_503 | http_504 | http_403 | http_404 | http_429 | non_idempotent | off ...;
Default: `error timeout`
Context: `http, server, location`

Like ```proxy_next_upstream```, specifies in which cases a request should be passed to the next server.

dubbo_next_upstream_tries
--------------------------

Syntax:	  **dubbo_next_upstream_tries**  *number*;
Default: `0`
Context: `http, server, location`

Like ```proxy_next_upstream_tries```, limits the number of possible tries for passing a request to the next server. The 0 value turns off this limitation.


dubbo_next_upstream_timeout
--------------------------

Syntax:	  **dubbo_next_upstream_timeout**  *timer*;
Default: `0`
Context: `http, server, location`

Like ```proxy_next_upstream_tries```, limits the time during which a request can be passed to the next server. The 0 value turns off this limitation.


dubbo_pass_header
--------------------------

Syntax:	  **dubbo_pass_header**  *field*;
Default: `none`
Context: `http, server, location`

Like ```proxy_pass_header```, permits passing otherwise disabled header fields from a Dubbo provider to a client.


dubbo_hide_header
--------------------------

Syntax:	  **dubbo_hide_header**  *field*;
Default: `none`
Context: `http, server, location`

Like ```proxy_hide_header```, by default, tengine does not pass the header fields "Date", "Server", and "X-Accel-..." from the response of a Dubbo provider to a client. The dubbo_hide_header directive sets additional fields that will not be passed. If, on the contrary, the passing of fields needs to be permitted, the dubbo_pass_header directive can be used.


Variables
=========

