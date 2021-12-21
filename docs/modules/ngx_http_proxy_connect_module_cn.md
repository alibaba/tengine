name
====

该模块提供对HTTP方法CONNECT的支持。（Tengine 2.3.0版本之后）  
该方法主要用于[SSL请求隧道](https://en.wikipedia.org/wiki/HTTP_tunnel#HTTP_CONNECT_tunneling)。

Table of Contents
=================

   * [name](#name)
   * [Example](#example)
      * [configuration example](#configuration-example)
      * [example for curl](#example-for-curl)
   * [Install](#install)
   * [Error Log](#error-log)
   * [Directive](#directive)
      * [proxy_connect](#proxy_connect)
      * [proxy_connect_allow](#proxy_connect_allow)
      * [proxy_connect_connect_timeout](#proxy_connect_connect_timeout)
      * [proxy_connect_read_timeout](#proxy_connect_read_timeout)
      * [proxy_connect_send_timeout](#proxy_connect_send_timeout)
      * [proxy_connect_address](#proxy_connect_address)
      * [proxy_connect_bind](#proxy_connect_bind)
   * [Variables](#variables)
      * [$connect_host](#connect_host)
      * [$connect_port](#connect_port)
      * [$connect_addr](#connect_addr)
      * [$proxy_connect_connect_timeout](#proxy_connect_connect_timeout-1)
      * [$proxy_connect_read_timeout](#proxy_connect_read_timeout-1)
      * [$proxy_connect_send_timeout](#proxy_connect_send_timeout-1)
   * [Known Issues](#known-issues)

Example
=======

Configuration Example
---------------------

```
 server {
     listen                         3128;

     # dns resolver used by forward proxying
     resolver                       8.8.8.8;

     # forward proxy for CONNECT request
     proxy_connect;
     proxy_connect_allow            443 563;
     proxy_connect_connect_timeout  10s;
     proxy_connect_read_timeout     10s;
     proxy_connect_send_timeout     10s;

     # forward proxy for non-CONNECT request
     location / {
         proxy_pass http://$host;
         proxy_set_header Host $host;
     }
 }
```

Example for curl
----------------

你可以通过HTTP CONNECT隧道访问任意HTTPS网站。  
使用命令`curl`的简单示例如下：

```
$ curl https://github.com/ -v -x 127.0.0.1:3128
*   Trying 127.0.0.1...                                           -.
* Connected to 127.0.0.1 (127.0.0.1) port 3128 (#0)                | curl与Tengine（proxy_connect模块）创建TCP连接。
* Establish HTTP proxy tunnel to github.com:443                   -'
> CONNECT github.com:443 HTTP/1.1                                 -.
> Host: github.com:443                                         (1) | curl发送CONNECT请求以创建隧道。
> User-Agent: curl/7.43.0                                          |
> Proxy-Connection: Keep-Alive                                    -'
>
< HTTP/1.0 200 Connection Established                             .- Tengine返回200说明隧道建立成功。
< Proxy-agent: nginx                                           (2)|  (后续客户端发送的任何数据都会被代理到对端，Tengine不会修改任何被代理的数据）
<                                                                 '-

* Proxy replied OK to CONNECT request
* TLS 1.2 connection using TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256  -.
* Server certificate: github.com                                   |
* Server certificate: DigiCert SHA2 Extended Validation Server CA  | curl通过隧道发送"https://github.com"请求，
* Server certificate: DigiCert High Assurance EV Root CA           | proxy_connect模块将把数据代理到对端（github.com）。
> GET / HTTP/1.1                                                   |
> Host: github.com                                             (3) |
> User-Agent: curl/7.43.0                                          |
> Accept: */*                                                     -'
>
< HTTP/1.1 200 OK                                                 .-
< Date: Fri, 11 Aug 2017 04:13:57 GMT                             |
< Content-Type: text/html; charset=utf-8                          |  任何来自对端的数据都会被proxy_connect模块发送给客户端curl。
< Transfer-Encoding: chunked                                      |
< Server: GitHub.com                                           (4)|
< Status: 200 OK                                                  |
< Cache-Control: no-cache                                         |
< Vary: X-PJAX                                                    |
...                                                               |
... <other response headers & response body> ...                  |
...                                                               '-
```

以上示例的流程图示例如下：

```
  curl                     nginx (proxy_connect)            github.com
    |                             |                          |
(1) |-- CONNECT github.com:443 -->|                          |
    |                             |                          |
    |                             |----[ TCP connection ]--->|
    |                             |                          |
(2) |<- HTTP/1.1 200           ---|                          |
    |   Connection Established    |                          |
    |                             |                          |
    |                                                        |
    ========= CONNECT 隧道已经被建立。========================
    |                                                        |
    |                             |                          |
    |                             |                          |
    |   [ SSL stream       ]      |                          |
(3) |---[ GET / HTTP/1.1   ]----->|   [ SSL stream       ]   |
    |   [ Host: github.com ]      |---[ GET / HTTP/1.1   ]-->.
    |                             |   [ Host: github.com ]   |
    |                             |                          |
    |                             |                          |
    |                             |                          |
    |                             |   [ SSL stream       ]   |
    |   [ SSL stream       ]      |<--[ HTTP/1.1 200 OK  ]---'
(4) |<--[ HTTP/1.1 200 OK  ]------|   [ < html page >    ]   |
    |   [ < html page >    ]      |                          |
    |                             |                          |
```

Install
=======

* 源码安装此模块：

```
$ ./configure --add-module=./modules/ngx_http_proxy_connect_module
$ make && make install
```

Error Log
=========

该模块记录的错误日志以`"proxy_connect:"`字符串为开头。  
典型的错误日志如下：

* proxy_connect模块尝试与后端服务器建立隧道连接，但发生了连接超时。

```
2019/08/07 17:27:20 [error] 19257#0: *1 proxy_connect: upstream connect timed out (peer:216.58.200.4:443) while connecting to upstream, client: 127.0.0.1, server: , request: "CONNECT www.google.com:443 HTTP/1.1", host: "www.google.com:443"
```

Directive
=========

proxy_connect
-------------

Syntax: **proxy_connect**  
Default: `none`  
Context: `server`  

开启对HTTP方法"CONNECT"的支持。

proxy_connect_allow
-------------------

Syntax: **proxy_connect_allow `all | [port ...] | [port-range ...]`**  
Default: `443 563`  
Context: `server`  

该指令指定允许开启CONNECT方法的端口。  
默认情况下，只有443和563端口被允许。  

使用如下参数来修改默认行为：

`all`值允许所有端口。

`port`指定允许的特定端口。

`port-range`指定允许的指定端口范围，示例：


```
proxy_connect_allow 1000-2000 3000-4000; # 允许端口范围1000-2000 和 3000-4000
```

proxy_connect_connect_timeout
-----------------------------

Syntax: **proxy_connect_connect_timeout `time`**  
Default: `none`  
Context: `server`  

指定与对端服务器建联的超时时间。

proxy_connect_read_timeout
--------------------------

Syntax: **proxy_connect_read_timeout `time`**  
Default: `60s`  
Context: `server`  

指定读对端服务器数据的等待时间。  
超时时间仅在两次读数据之间生效，而不是整个应答数据时间。  
如果对端服务器在超时时间内未发送任何数据，连接将被关闭。

proxy_connect_send_timeout
--------------------------

Syntax: **proxy_connect_send_timeout `time`**  
Default: `60s`  
Context: `server`  

指定发送数据到对端服务器的等待时间。  
超时时间仅在两次发送数据之间生效，而不是整个请求时间。  
如果对端服务器在等待时间内未收取任何数据，连接将被关闭。

proxy_connect_address
---------------------

Syntax: **proxy_connect_address `address | off`**  
Default: `none`  
Context: `server`  

指定对端服务器的地址。该值可以包含变量。  
值`off`或者不设置该指令，则对端服务器的地址将CONNECT请求行的host字段提取并解析（如查询DNS）。  

proxy_connect_bind
------------------

Syntax: **proxy_connect_bind `address [transparent] | off`**  
Default: `none`  
Context: `server`  

指定与对端服务器的连接的来源地址。  
该值可以包含变量。值`off`或者不设置该指令将由系统自动分配来源地址和端口。  

`transparent`参数值使与对端服务器的连接的来源地址为非本地地址。示例如下（使用客户端地址作为来源地址）：  

```
proxy_connect_bind $remote_addr transparent;

```

为了使`transparent`参数生效，需要配置内核路由表去截获来自对端服务器的网络流量。

Variables
=========

$connect_host
-------------

CONNECT请求行的主机名(host)字段。

$connect_port
-------------

CONNECT请求行的端口(port)字段。

$connect_addr
-------------

对端服务器的IP地址和端口，如"192.168.1.5:12345"。

$proxy_connect_connect_timeout
------------------------------

获取和设置[`proxy_connect_connect_timeout`指令](#proxy_connect_connect_timeout)的超时时间。

示例如下：

```
# 设置默认值

proxy_connect_connect_timeout   10s;
proxy_connect_read_timeout      10s;
proxy_connect_send_timeout      10s;

# 覆盖默认值

if ($host = "test.com") {
    set $proxy_connect_connect_timeout  "10ms";
    set $proxy_connect_read_timeout     "10ms";
    set $proxy_connect_send_timeout     "10ms";
}
```

$proxy_connect_read_timeout
---------------------------

获取和设置[`proxy_connect_read_timeout`指令](#proxy_connect_read_timeout)的超时时间。

$proxy_connect_send_timeout
---------------------------

获取和设置[`proxy_connect_send_timeout`指令](#proxy_connect_send_timeout)的超时时间。

Known Issues
============

* 不支持HTTP/2的CONNECT方法。CONNECT方法仅支持HTTP/1.x和HTTPS。

See Also
========

* [维基百科：HTTP隧道](https://en.wikipedia.org/wiki/HTTP_tunnel)
* [HTTP/1.1协议中CONNECT方法](https://tools.ietf.org/html/rfc7231#section-4.3.6)
* [HTTP/2协议中CONNECT方法](https://httpwg.org/specs/rfc7540.html#CONNECT)

