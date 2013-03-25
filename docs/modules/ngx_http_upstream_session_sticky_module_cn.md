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
            proxy_pass http://foo;
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
        #在insert + indirect模式或者prefix模式下需要配置session_sticky_hide_cookie
        #这种模式不会将保持会话使用的cookie传给后端服务，让保持会话的cookie对后端透明
        session_sticky_hide_cookie upstream=test;
        proxy_pass http://test;
      }
    }

# 指令 #

## session_sticky ##

语法：**session_sticky** `[cookie=name] [domain=your_domain] [path=your_path] [maxage=time] [mode=insert|rewrite|prefix] [option=indirect] [maxidle=time] [maxlife=time] [fallback=on|off] [hash=plain|md5]`

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
    - **prefix**: 不会生成新的cookie，但会在响应的cookie值前面加上特定的前缀，当浏览器带着这个有特定标识的cookie再次请求时，模块在传给后端服务前先删除加入的前缀，后端服务拿到的还是原来的cookie值，这些动作对后端透明。如："Cookie: NAME=SRV~VALUE"。
    - **rewrite**: 使用服务端标识覆盖后端设置的用于session sticky的cookie。如果后端服务在响应头中没有设置该cookie，则认为该请求不需要进行session sticky，使用这种模式，后端服务可以控制哪些请求需要sesstion sticky，哪些请求不需要。

+ `option` 设置用于session sticky的cookie的选项，可设置成indirect或direct。indirect不会将session sticky的cookie传送给后端服务，该cookie对后端应用完全透明。direct则与indirect相反。
+ `maxidle`设置session cookie的最长空闲的超时时间
+ `maxlife`设置session cookie的最长生存期
+ `fallback`设置是否重试其他机器，当sticky的后端机器挂了以后，是否需要尝试其他机器
+ `hash` 设置cookie中server标识是用明文还是使用md5值，默认使用md5

## session\_sticky\_hide\_cookie ##

语法: **session\_sticky\_hide\_cookie** upstream=name;

默认值: none

上下文： server, location

说明：

配合proxy_pass指令使用。用于在insert+indirect模式和prefix模式下删除请求用于session sticky的cookie，这样就不会将该cookie传递给后端服务。upstream表示需要进行操作的upstream名称。
