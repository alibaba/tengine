# Name 模块
**ngx\_http\_upstream\_session\_sticky\_module**

该模块是一个负载均衡模块，通过cookie实现客户端与后端服务器的会话保持, 在一定条件下可以保证同一个客户端访问的都是同一个后端服务器。

# Example 1#

    # 默认配置：cookie=route mode=insert fallback=on
    upstream foo {
       server 192.168.0.1;
       server 192.168.0.2;
       session_sticky;
    }

    server {
        location / {
            proxy_pass http://test;
        }
    }

# Example 2#

    #insert + indirect模式：
    upstream test {
      session_sticky session_sticky cookie=uid domain=www.xxx.com fallback=on path=/ mode=insert option=indirect;
      server  127.0.0.1:8080;
    }

    server {
      location / {
        #在insert + indirect模式或者prefix模式下需要配置session_sticky_header
        #它可以删除本模块用来会话保持的cookie, 让后端完全感觉不到会话保持的存在
        session_sticky_header upstream=test switch=on;
        proxy_pass http://test;
      }
    }

# 指令 #

## session_sticky ##

语法：**session_sticky** `[cookie=name] [domain=your_domain] [path=your_path] [maxage=time] [mode=insert|rewrite|prefix] [option=indirect] [maxidle=time] [maxlife=time] [fallback=on|off]`

默认值：`session_sticky cookie=route mode=insert fallback=on`

上下文：`upstream`

说明:

本指令可以打开会话保持的功能，下面是具体的参数：

+ `cookie`设置用来记录会话的cookie名称
+ `domain`设置cookie作用的域名，默认不设置
+ `path`设置cookie作用的URL路径，默认不设置
+ `maxage`设置cookie的生存期，默认不设置，即为session cookie，浏览器关闭即失效
+ `mode`设置cookie的模式:
    - **insert**: 在回复中本模块通过Set-Cookie头直接插入相应名称的cookie。
    - **prefix**: 不会发出新的cookie，它会在已有的Set-Cookie的值前面插入服务器标识符。当请求带着这个修改过的cookie再次来请求时，它会删除前面的标识符，然后再传给后端服务器，所以服务器还能使用原来的cookie。它修改过的cookie形式如："Cookie: NAME=SRV~VALUE"。
    - **rewrite**: cookie是由后端服务器提供的，在回复中看到该cookie，它可以把这个cookie完全用服务器标识符修改掉。这样做的好处是，服务器可以控制哪些请求可以session sticky，如果后端没有发出Set-Cookie头，就说明这些请求都不需要session sticky。

+ `option`设置cookie的一些选项:
    - **indirect**: 当客户端携带会话保持cookie过来访问时，将请求转发给后端时，该cookie会被删除, 所以这个会话保持cookie对于后端的应用完全是透明的。本指令需要跟`session_sticky_header`结合使用，才能真正删除cookie。
+ `maxidle`设置session cookie的最长空闲的超时时间, 如果在这段时间内浏览器没有任何动作，cookie就失效。客户端每次访问都会更新这个时间。
+ `maxlife`设置session cookie的最长生存期, 超过了这段时间，cookie失效。
+ `fallback`设置是否重试其他机器，当sticky的后端机器宕机了以后，是否需要尝试其他机器。

## session\_sticky\_header ##

语法: **session\_sticky\_header** upstream=name [switch=[on|off]];

默认值: none

上下文： server, location

说明：

需要跟`proxy_pass`指令结合使用，在`insert`+`indirect`模式和`prefix`模式下，当客户端携带会话cookie过来访问时，该指令会删除该cookie。参数`upstream`是设置需要处理cookie的upsteam名称, 参数`switch`是关闭或者开启对于cookie的处理。出现这个指令的原因是，在upstream块内的函数，不能删除或者修改cookie，不得已我们在location里面加了这个冗余的指令。
