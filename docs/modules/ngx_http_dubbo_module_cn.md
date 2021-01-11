ngx_http_dubbo_module
=================

该模块提供对后端Dubbo服务体系对接的支持。（Tengine 2.3.2版本之后）
[Apache Dubbo™](http://dubbo.apache.org) 是一款高性能Java RPC框架。最初由Alibaba开源，经过长期发展和演进，目前已经成为业界主流微服务框架之一。

在Dubbo服务框架中包含Consumer（client）和Provider（Server）两个角色。该模块支持Tengine作为网关代理，前端接收HTTP/HTTPS/HTTP2等请求，后端作为Dubbo的Consumer调用Dubbo的Provider服务（业务）。

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
===================

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
### 标准方式下

Dubbo Provider侧需要实现如下接口，然后将服务名、服务版本号、方法名配置到```dubbo_pass```中。Tengine将前端HTTP/HTTPS/HTTP2请求，转换为对如下Dubbo接口的调用。

```
Map<String, Object> dubbo_method(Map<String, Object> context);

```

其中，方法入参Map<String, Object> context中包含若干键值对，可以通过```dubbo_pass_set```、```dubbo_pass_all_headers```、```dubbo_pass_body```等指令进行调整，如下Key为有特殊含义的规定：
```
body： HTTP请求的Body，value的Object类型为byte[]

```

方法返回值中，如下Key为有特殊含义的规定：
```
body： HTTP响应的Body，value的Object类型为byte[]
statue: HTTP响应的状态码，value的类型为String
```



### 扩展方式（持续更新中，敬请期待）

支持在Tengine侧配置参数映射，动态生成对后端任意Dubbo Provider方法的调用（持续更新中，敬请期待）。


QuickStart
=======
这里有一个[Tengine Dubbo功能的QuickStart](https://github.com/apache/dubbo-samples/tree/master/dubbo-samples-tengine)


Install
=======

源码安装此模块：

```
$ ./configure --add-module=./modules/mod_dubbo --add-module=./modules/ngx_multi_upstream_module --add-module=./modules/mod_config
$ make && make install
```

Dynamic module 支持
* mod_dubbo: ```支持```编译成 dynamic module
* ngx_multi_upstream_module: ```不支持```编译成 dynamic module
* mod_config: ```支持但无需```编译成 dynamic module


Directive
=========

dubbo_pass
-------------
Syntax: **dubbo_pass** *service_name* *service_version* *method* *upstream_name*  
Default: `none`  
Context: `location, if in location` 

该指令用于配置使用Dubbo协议，代理到后端upstream 

*service_name*: Dubbo provider发布的服务名
*service_version*: Dubbo provider发布的服务版本号
*method*: Dubbo provider发布的服务方法
*upstream_name*: 后端upstream名称

`service_name`、`service_version`、`method` 支持使用变量。

```
# 代理到dubbo_backend这个upstream
upstream dubbo_backend {
    multi 1;
    server 127.0.0.1:20880;
}

set $dubbo_service_name "org.apache.dubbo.demo.DemoService";
set $dubbo_service_name "0.0.0";
set $dubbo_service_name "http_dubbo_nginx";

dubbo_pass $dubbo_service_name $dubbo_service_version $dubbo_method dubbo_backend;
```

注意：

`dubbo_pass`只支持multi模式的upstream，相关upstream，必须通过`multi`指令，配置为多路复用模式，multi指令的参数为，多路复用连接的个数。


dubbo_pass_set
-------------------

Syntax: **dubbo_pass_set** *key* *value*;  
Default: `none`  
Context: `location, if in location`  

该指令用于设置，代理到后端时，需要携带哪些key、value，支持变量。

```
dubbo_pass_set username $cookie_user;
```

dubbo_pass_all_headers
-----------------------------

Syntax: **dubbo_pass_all_headers** on | off;
Default: `off`
Context: `location, if in location`

指定是否向后端自动携带所有http头的key、value对。

dubbo_pass_body
--------------------------

Syntax: **dubbo_pass_body** on | off;
Default: `on`
Context: `location, if in location`

指定是否向后端携带请求Body。

dubbo_heartbeat_interval
--------------------------

Syntax: **dubbo_heartbeat_interval** *time*;
Default: `60s`
Context: `http, server, location`

指定后端Dubbo连接，自动发送ping帧的间隔。

dubbo_bind
--------------------------

Syntax:	  **dubbo_bind**  *address* [transparent ] | off;
Default: `off`
Context: `http, server, location`

类似```proxy_bind```指令，提供Dubbo连接时指定本地IP Port。当设置为off时，使用操作系统自动分配的本地IP地址和Port。当设置为transparent时，使用指定的非本地IP地址连接后端。

```
dubbo_bind $remote_addr transparent;
```

dubbo_socket_keepalive
--------------------------

Syntax:	  **dubbo_socket_keepalive**  on | off;
Default: `off`
Context: `http, server, location`

类似```proxy_socket_keepalive```指令，配置 “TCP keepalive” 选项，当设置为on是，后端Dubbo连接将设置 SO_KEEPALIVE socket选项。

dubbo_connect_timeout
--------------------------

Syntax:	  **dubbo_connect_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

类似```proxy_connect_timeout```指令，配置后端Dubbo建立TCP连接的超时，注意，这个时间通常不超过75s。

dubbo_send_timeout
--------------------------

Syntax:	  **dubbo_send_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

类似```proxy_send_timeout```指令，配置后端Dubbo连接发送超时，这个超时仅代表两次相邻的成功write操作，而不是整个请求的处理时间。

dubbo_read_timeout
--------------------------

Syntax:	  **dubbo_read_timeout**  *time*;
Default: `60s`
Context: `http, server, location`

类似```proxy_read_timeout```指令，配置后端Dubbo连接读取超时，这个超时仅代表两次相邻的成功read操作，而不是整个请求的处理时间。


dubbo_intercept_errors
--------------------------

Syntax:	  **dubbo_intercept_errors**  on | off;
Default: `off`
Context: `http, server, location`

类似```proxy_intercept_errors```指令，指定后端返回的状态码大于300时，使用```error_page```处理还是直接返回给客户端。


dubbo_buffer_size
--------------------------

Syntax:	  **dubbo_buffer_size**  *size*;
Default: `4k|8k`
Context: `http, server, location`

类似```proxy_buffer_size```指令，指定读取后端Dubbo response时buffer的大小。

dubbo_next_upstream
--------------------------

Syntax:	  **dubbo_next_upstream**  error | timeout | invalid_header | http_500 | http_502 | http_503 | http_504 | http_403 | http_404 | http_429 | non_idempotent | off ...;
Default: `error timeout`
Context: `http, server, location`

类似```proxy_next_upstream```指令，指定对请求进行next server的条件。

dubbo_next_upstream_tries
--------------------------

Syntax:	  **dubbo_next_upstream_tries**  *number*;
Default: `0`
Context: `http, server, location`

类似```proxy_next_upstream_tries```指令，指定可以对请求进行next server的次数，0的话，代表不进行next server。


dubbo_next_upstream_timeout
--------------------------

Syntax:	  **dubbo_next_upstream_timeout**  *timer*;
Default: `0`
Context: `http, server, location`

类似```proxy_next_upstream_tries```指令，指定可以对请求进行next server的次数，0的话，代表不进行next server。


dubbo_pass_header
--------------------------

Syntax:	  **dubbo_pass_header**  *field*;
Default: `none`
Context: `http, server, location`

类似```proxy_pass_header```指令，默认情况下，Tengine不向客户端传递，后端Server返回的 “Date”, “Server”, and “X-Accel-...”，该指令用于允许向客户端传递指定的头。


dubbo_hide_header
--------------------------

Syntax:	  **dubbo_hide_header**  *field*;
Default: `none`
Context: `http, server, location`

类似```proxy_hide_header```指令，默认情况下，Tengine不向客户端传递，后端Server返回的 “Date”, “Server”, and “X-Accel-...”，该指令用于增加不向客户端传递的头。


Variables
=========



