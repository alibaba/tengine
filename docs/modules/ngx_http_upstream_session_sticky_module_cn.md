# Name 模块
**ngx_http_upstream_session_sticky_module**

该模块的功能是通过cookie实现客户端与后端服务器的映射。

# Example 1#
    默认配置：cookie=route mode=insert fallback=on
    upstream foo {
       server 192.168.0.1;
       server 192.168.0.2;
       session_sticky;
    }
    server {
        location / {
            #在insert 或者rewrite 模式不需要配置session_sticky_header
            proxy_pass http://test;
        }
    }
# Example 2#

    #insert + indirect 模式：
    upstream test {
      session_sticky session_sticky cookie=uid domain=www.xxx.com fallback=on path=/ mode=insert option=indirect;
      server  127.0.0.1:8080;
    }
    server {
      location / {
        #在insert + indirect模式或者 prefix模式下需要配置session_sticku_header
        session_sticky_header upstream=test switch=on;
        proxy_pass http://test;
      }
    }

# 指令 #

## session_sticky ##

语法：session_sticky [cookie=name] [domain=your_domain] [path=your_path] [maxage=time] [mode=insert|rewrite|prefix] [option=indirect] [maxidle=time] [maxlife=time] [fallback=on|off] 

默认值：session_sticky cookie=route mode=insert fallback=on

上下文：upstream

说明：

+   cookie参数设置的cookie名称
+   domain设置cookie作用的域名，默认不设置
+   path设置cookie作用的URL，默认不设置
+   maxage设置cookie的生存期，默认不设置，为session cookie，浏览器关闭即失效。
+   mode设置cookie的模式

    **insert**: 回复中插入相应名字cookie 

    **prefix**:不会发出新的cookie，它会在已有的Set-Cookie的值前面插入服务器标识符。
    当请求带着这个修改过的cookie来请求时，它会删除前面的标识符，然后再传给后端服务器，
    所以服务器还能用原来的cookie。它修改过的cookie形式如："Cookie: NAME=SRV~VALUE" 

    **rewrite**:这个选项表明cookie是由后端服务器提供的，在回复中看到该cookie，
    它可以把这个cookie完全用服务器标识符修改掉。这样做的好处是，
    服务器可以控制哪些请求可以session sticky，如果后端没有发出set-cookie头，
    就说明这些请求都不需要session sticky。

+   option设置cookie的一些选项，indirect选项，请求过来时，插入的cookie会被tengine删除，
这个cookie对于后端的应用完全是透明的。现在只实现该选项。
+   maxidle设置session cookie的最长空闲的超时时间
+   maxlinfe设置session cookie的最长生存期
+   fallback设置是否重试其他机器，当sticky的后端机器挂了以后，是否需要尝试其他机器

## session_sticky_header ##

语法: session_sticky_header upstream=name [switch=[on|off]];

默认值: none

上下文： server, location

说明：

在insert+indirect模式和prefix模式下，必须跟proxy_pass指令结合使用这个指令。rewrite模式可以不配置这个指令。upstream是需要处理cookie的upsteam名称switch是关闭或者开启对于cookie的处理出现这个指令的原因是，在upstream块内的函数，都不能删除或者修改cookie，不得已我们加了这个重复的指令。
