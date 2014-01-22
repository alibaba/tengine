# Name #

**ngx\_http\_spdy\_module**

Tengine对SPDY模块增加SPDY/3协议的支持。以下是新增的指令。


# Directives #

## spdy\_version ##

Syntax: **spdy\_version** [2|3]

Default: 3

Context: http, server

指定SPDY协议使用的版本。默认是SPDY/3。

## spdy\_flow\_control ##

Syntax: **spdy\_flow\_control** on|off

Default: on

Context: http, server

打开或关闭SPDY/3的流控功能。

## spdy\_init\_recv\_window\_size ##

Syntax: **spdy\_init\_recv\_window\_size** size

Default: 64k

Context: http, server

指定SPDY/3服务器的接收窗口大小。接收窗口大小默认值是64K。服务器每次会在接收窗口使用超过一半时给客户端发送窗口更新帧(WINDOW UPDATE frame)。

## spdy\_detect ##

Syntax: listen address[:port] [spdy_detect] [ssl]

Default:

Context: listen directive

启用这个指令时，SPDY协议和HTTP协议可以工作在同一个端口上。注意：服务器通过探测每个TCP连接上的首字节来判断此连接上是SPDY协议还是HTTP协议(如果首字节是0x80或者0x00，则认为是SPDY协议)。

服务器在80端口上同时监听SPDY连接和HTTP连接，配置如下：

    listen 80 spdy_detect;

服务器在443端口上自动探测SSL层下是SPDY协议还是HTTP协议。注意服务器不会通过TLS扩展(NPN)来协商是SPDY协议还是HTTP协议，配置如下：

    listen 443 ssl spdy_detect;

服务器在443端口上既可以自动探测SSL层下是SPDY协议还是HTTP协议，也可以通过TLS扩展(NPN)来协商是SPDY协议还是HTTP协议，配置如下：

    listen 443 ssl spdy_detect spdy;


