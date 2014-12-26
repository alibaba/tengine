名称
====

ngx_http_copy_module

描述
====

该模块可以拷贝实时的http请求到指定的地方，并且不会影响原请求的处理。<br>
该模块会接受所有拷贝的请求的应答，并丢弃这些应答。

我们可以用该模块拷贝在线流量到任何地方来做测试或者分析。

该模块只能工作于Tengine，它使用了Tengine的请求体过滤器。<br>
(该模块的标准nginx版本: [ngx_http_copy_module](http://github.com/chobits/ngx_http_copy_module))

如果前端开启了https/spdy，进入的https/spdy请求在拷贝到后端时，会被转化成HTTP请求。


编译
====

该模块默认没有编译到Tengine中。<br>
可以通过编译参数'--with-http_copy_module'来开启该模块的编译，<br>
或者通过编译参数'--with-http_copy_module=shared'来将该模块编译成'.so'。


示例
====

```
http {

    server {
        listen 80;

        # 拷贝流量到这两台测试机器
        http_copy 127.0.0.1:7001;
        http_copy 127.0.0.1:7002 multiple=2;    # 1个请求被拷贝成2份

        location / {
            proxy_pass http://backend;
        }

        location = /http_copy_status {
            # 对于访问"/http_copy_status"的请求，关闭拷贝
            http_copy off;
            http_copy_status;
        }
    }
}
```

上述配置会将请求转到后端backend机器上，<br>
并且将请求拷贝到测试机器(127.0.0.1:7001 & :7002)，请求流向如下:

```
client --> (tengine) --> (backend)
                  ‖ |
                  ‖ '--> (127.0.0.1:7001)
                  ‖
                  `====> (127.0.0.1:7002)
```

指令
====

http_copy
---------

**Syntax**:
* http_copy address [multiple=\<n>] [connections=\<n>] [switch_on=$nginx_variable] [fail_timeout=\<time>] [max_fails=\<n>] [serial];
* http_copy off;

**Default**: none

**Context**: main, server, location, if

**Example**: `http_copy 127.0.0.1:7001 mutiple=4 connections=512 switch_on=$is_http_get fail_timeout=10s max_fails=1 serial;`

**Parameters**:
* `mutilple`:
   设置请求拷贝的倍数。(默认1倍)
* `connections`:
   设置请求拷贝允许使用的最大连接数。(默认65535)
*  `max_fails`:
   设置与服务器通信的连续尝试失败的次数。(默认5)<br>
   如果连续失败的次数达到此值 (**>= max_fails**)，就认为服务器不可用。<br>
   在下一个fail_timeout时间段内，请求将不会被拷贝到该服务器。<br>
   设置为0，就不统计尝试次数。无论服务器是否可用，会一直尝试拷贝请求到该服务器。
*  `fail_timeout`:
   服务器被认为不可用的时间段。(默认10s)
* `serial`:
   将原请求的多份拷贝通过1个连接发送(类似http pipelining)。<br>
   如果拷贝的倍数较大，开启该选项可以有效地限制并发连接数。
* `switch_on`:
   设置开关变量来决定是否开启http_copy指令。<br>
   如果开关变量的值为"true"，http_copy指令将开启。

```
# 示例: 只拷贝GET请求

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
  设置连接的最大缓存数。拷贝的请求将重用缓存的连接。
* `timeout`:
  设置缓存连接的超时。该值的单位是毫秒。<br>
  如果缓存的连接在超时时间内一直没有被使用，该连接将被关闭。
* `force_off`:
  默认情况下，拷贝的请求的version字段将被设置成"HTTP/1.1"，并且"Connection:"头将被删除。<br>
  如果设置了force_off，上述默认行为将无效。

http_copy_unparsed_uri
----------------------

**Syntax**: http_copy_unparsed_uri on|off;

**Default**: http_copy_unparsed_uri on;

**Context**: main, server, location

决定拷贝的请求的uri是原始uri ($request_uri)还是最终的uri ($uri)。<br>
如果开启，拷贝的请求的uri是请求的原始uri ($request_uri)。

```
# 示例: 拷贝的请求使用改写的uri
# 访问"/acbd18.jpg"的请求将被拷贝到127.0.0.1:7001，拷贝的请求的uri将是"/jpg/acbd18"。

server {
   http_copy 127.0.0.1:7001;
   http_copy_unparsed_uri off;

   rewrite (.*)\.jpg /jpg/$1 break;    # 将uri从"/XXX.jpg"改写成"/jpg/XXX"

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

从该location下获取流量拷贝的统计信息。

```
# 示例: 获取统计信息
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
 - **Request**: 拷贝的总请求数
 - **Response**: 接收到拷贝请求的总应答数量
 - **Response(OK)**: 2XX，3XX应答的数量
 - **Response(ERROR)**: 4XX，5XX和其他状态码应答的数量
 - **Connect**: 建立的总连接
 - **Connect(keepalive)**: 连接复用的次数
 - **read**: 后端系统发回HTTP应答的总数据量(只统计HTTP BODY, 忽略HTTP STATUS LINE & HEADERS)
 - **read(chunk)**: 后端系统发回HTTP应答的总数据量(只统计HTTP CHUNK BODY)
 - **write**: 未实现，总是0
- **real time**:
 - **Connect**: 当前建立的连接数
 - **Connect(keepalive)**: 当前复用的连接数
