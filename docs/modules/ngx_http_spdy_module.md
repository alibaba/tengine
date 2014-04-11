# Name #

**ngx\_http\_spdy\_module**

Tengine added SPDY/3 support to this module. The new directives are listed below.


# Directives #

## spdy\_version ##

Syntax: **spdy\_version** [2|3]

Default: 3

Context: http, server

Specify the version of current SPDY protocol.

## spdy\_flow\_control ##

Syntax: **spdy\_flow\_control** on|off

Default: on

Context: http, server

Turn on or off with SPDY flow control.

## spdy\_init\_recv\_window\_size ##

Syntax: **spdy\_init\_recv\_window\_size** size

Default: 64k

Context: http, server

Specify the receiving window size for SPDY. By default, it's 64K. It will send a WINDOW UPDATE frame when it receives half of the window size data every time.

## spdy\_detect ##

Syntax: listen address[:port] [spdy_detect] [ssl]

Default:

Context: listen directive

Server can work for SPDY and HTTP on the same port with this directive. Note that the server will examine the first byte of one connection and determine whether the connection is SPDY or HTTP based on what it looks like (0x80 or 0x00 for SPDY).

Server will listen on port 80 for SPDY and HTTP, for example:

    listen 80 spdy_detect;

Server will detect whether SPDY or HTTP is used without using a TLS extension (NPN), for example:

    listen 443 ssl spdy_detect;

Server can detect whether SPDY or HTTP is used directly, and also it can negotiate with client via NPN, for example:

    listen 443 ssl spdy_detect spdy;


