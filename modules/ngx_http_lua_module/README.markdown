Name
====

ngx_http_lua_module - Embed the power of Lua into Nginx HTTP Servers.

This module is a core component of [OpenResty](https://openresty.org). If you are using this module,
then you are essentially using OpenResty.

*This module is not distributed with the Nginx source.* See
[the installation instructions](#installation).

This is a core component of OpenResty. If you are using this module, then you are essentially using OpenResty :)

Table of Contents
=================

* [Name](#name)
* [Status](#status)
* [Version](#version)
* [Videos](#videos)
* [Synopsis](#synopsis)
* [Description](#description)
* [Typical Uses](#typical-uses)
* [Nginx Compatibility](#nginx-compatibility)
* [Installation](#installation)
    * [Building as a dynamic module](#building-as-a-dynamic-module)
    * [C Macro Configurations](#c-macro-configurations)
* [Community](#community)
    * [English Mailing List](#english-mailing-list)
    * [Chinese Mailing List](#chinese-mailing-list)
* [Code Repository](#code-repository)
* [Bugs and Patches](#bugs-and-patches)
* [LuaJIT bytecode support](#luajit-bytecode-support)
* [System Environment Variable Support](#system-environment-variable-support)
* [HTTP 1.0 support](#http-10-support)
* [Statically Linking Pure Lua Modules](#statically-linking-pure-lua-modules)
* [Data Sharing within an Nginx Worker](#data-sharing-within-an-nginx-worker)
* [Known Issues](#known-issues)
    * [TCP socket connect operation issues](#tcp-socket-connect-operation-issues)
    * [Lua Coroutine Yielding/Resuming](#lua-coroutine-yieldingresuming)
    * [Lua Variable Scope](#lua-variable-scope)
    * [Locations Configured by Subrequest Directives of Other Modules](#locations-configured-by-subrequest-directives-of-other-modules)
    * [Cosockets Not Available Everywhere](#cosockets-not-available-everywhere)
    * [Special Escaping Sequences](#special-escaping-sequences)
    * [Mixing with SSI Not Supported](#mixing-with-ssi-not-supported)
    * [SPDY Mode Not Fully Supported](#spdy-mode-not-fully-supported)
    * [Missing data on short circuited requests](#missing-data-on-short-circuited-requests)
* [TODO](#todo)
* [Changes](#changes)
* [Test Suite](#test-suite)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)
* [Directives](#directives)
* [Nginx API for Lua](#nginx-api-for-lua)
* [Obsolete Sections](#obsolete-sections)
    * [Special PCRE Sequences](#special-pcre-sequences)
    * [Lua/LuaJIT bytecode support](#lualuajit-bytecode-support)

Status
======

Production ready.

Version
=======

This document describes ngx_lua
[v0.10.19](https://github.com/openresty/lua-nginx-module/tags), which was released
on 3 Nov, 2020.

Videos
======

* YouTube video "[Hello World HTTP Example with OpenResty/Lua](https://youtu.be/eSfYLvVQMxw)"

    [![Hello World HTTP Example with OpenResty/Lua](https://img.youtube.com/vi/eSfYLvVQMxw/0.jpg)](https://youtu.be/eSfYLvVQMxw)

* YouTube video "[Write Your Own Lua Modules in OpenResty/Nginx Applications](https://youtu.be/vfYxOMl5LVY)"

    [![Write Your Own Lua Modules in OpenResty/Nginx Applications](https://img.youtube.com/vi/vfYxOMl5LVY/0.jpg)](https://youtu.be/vfYxOMl5LVY)

* YouTube video "[OpenResty's resty Command-Line Utility Demo](https://youtu.be/L1c7aw4mSOo)"

    [![OpenResty's resty Command-Line Utility Demo](https://img.youtube.com/vi/L1c7aw4mSOo/0.jpg)](https://youtu.be/L1c7aw4mSOo)

* YouTube video "[Measure Execution Time of Lua Code Correctly in OpenResty](https://youtu.be/VkRYW_qLoME)"

    [![Measure Execution Time of Lua Code Correctly in OpenResty](https://img.youtube.com/vi/VkRYW_qLoME/0.jpg)](https://youtu.be/VkRYW_qLoME)

* YouTube video "[Precompile Lua Modules into LuaJIT Bytecode to Speedup OpenResty Startup](https://youtu.be/EP7c0BM2yNo)"

    [![Precompile Lua Modules into LuaJIT Bytecode to Speedup OpenResty Startup](https://img.youtube.com/vi/EP7c0BM2yNo/0.jpg)](https://youtu.be/EP7c0BM2yNo)

You are welcome to subscribe to our [official YouTube channel, OpenResty](https://www.youtube.com/channel/UCXVmwF-UCScv2ftsGoMqxhw).

[Back to TOC](#table-of-contents)

Synopsis
========
```nginx

 # set search paths for pure Lua external libraries (';;' is the default path):
 lua_package_path '/foo/bar/?.lua;/blah/?.lua;;';

 # set search paths for Lua external libraries written in C (can also use ';;'):
 lua_package_cpath '/bar/baz/?.so;/blah/blah/?.so;;';

 server {
     location /lua_content {
         # MIME type determined by default_type:
         default_type 'text/plain';

         content_by_lua_block {
             ngx.say('Hello,world!')
         }
     }

     location /nginx_var {
         # MIME type determined by default_type:
         default_type 'text/plain';

         # try access /nginx_var?a=hello,world
         content_by_lua_block {
             ngx.say(ngx.var.arg_a)
         }
     }

     location = /request_body {
         client_max_body_size 50k;
         client_body_buffer_size 50k;

         content_by_lua_block {
             ngx.req.read_body()  -- explicitly read the req body
             local data = ngx.req.get_body_data()
             if data then
                 ngx.say("body data:")
                 ngx.print(data)
                 return
             end

             -- body may get buffered in a temp file:
             local file = ngx.req.get_body_file()
             if file then
                 ngx.say("body is in file ", file)
             else
                 ngx.say("no body found")
             end
         }
     }

     # transparent non-blocking I/O in Lua via subrequests
     # (well, a better way is to use cosockets)
     location = /lua {
         # MIME type determined by default_type:
         default_type 'text/plain';

         content_by_lua_block {
             local res = ngx.location.capture("/some_other_location")
             if res then
                 ngx.say("status: ", res.status)
                 ngx.say("body:")
                 ngx.print(res.body)
             end
         }
     }

     location = /foo {
         rewrite_by_lua_block {
             res = ngx.location.capture("/memc",
                 { args = { cmd = "incr", key = ngx.var.uri } }
             )
         }

         proxy_pass http://blah.blah.com;
     }

     location = /mixed {
         rewrite_by_lua_file /path/to/rewrite.lua;
         access_by_lua_file /path/to/access.lua;
         content_by_lua_file /path/to/content.lua;
     }

     # use nginx var in code path
     # CAUTION: contents in nginx var must be carefully filtered,
     # otherwise there'll be great security risk!
     location ~ ^/app/([-_a-zA-Z0-9/]+) {
         set $path $1;
         content_by_lua_file /path/to/lua/app/root/$path.lua;
     }

     location / {
        client_max_body_size 100k;
        client_body_buffer_size 100k;

        access_by_lua_block {
            -- check the client IP address is in our black list
            if ngx.var.remote_addr == "132.5.72.3" then
                ngx.exit(ngx.HTTP_FORBIDDEN)
            end

            -- check if the URI contains bad words
            if ngx.var.uri and
                   string.match(ngx.var.request_body, "evil")
            then
                return ngx.redirect("/terms_of_use.html")
            end

            -- tests passed
        }

        # proxy_pass/fastcgi_pass/etc settings
     }
 }
```

[Back to TOC](#table-of-contents)

Description
===========

This module embeds [LuaJIT 2.0/2.1](https://luajit.org/luajit.html) into Nginx.
It is a core component of [OpenResty](https://openresty.org). If you are using
this module, then you are essentially using OpenResty.

Since version `v0.10.16` of this module, the standard Lua
interpreter (also known as "PUC-Rio Lua") is not supported anymore. This
document interchangeably uses the terms "Lua" and "LuaJIT" to refer to the
LuaJIT interpreter.

By leveraging Nginx's subrequests, this module allows the integration of the
powerful Lua threads (known as Lua "coroutines") into the Nginx event model.

Unlike [Apache's mod_lua](https://httpd.apache.org/docs/trunk/mod/mod_lua.html)
and [Lighttpd's mod_magnet](http://redmine.lighttpd.net/wiki/1/Docs:ModMagnet),
Lua code executed using this module can be *100% non-blocking* on network
traffic as long as the [Nginx API for Lua](#nginx-api-for-lua) provided by
this module is used to handle requests to upstream services such as MySQL,
PostgreSQL, Memcached, Redis, or upstream HTTP web services.

At least the following Lua libraries and Nginx modules can be used with this
module:

* [lua-resty-memcached](https://github.com/openresty/lua-resty-memcached)
* [lua-resty-mysql](https://github.com/openresty/lua-resty-mysql)
* [lua-resty-redis](https://github.com/openresty/lua-resty-redis)
* [lua-resty-dns](https://github.com/openresty/lua-resty-dns)
* [lua-resty-upload](https://github.com/openresty/lua-resty-upload)
* [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)
* [lua-resty-lock](https://github.com/openresty/lua-resty-lock)
* [lua-resty-logger-socket](https://github.com/cloudflare/lua-resty-logger-socket)
* [lua-resty-lrucache](https://github.com/openresty/lua-resty-lrucache)
* [lua-resty-string](https://github.com/openresty/lua-resty-string)
* [ngx_memc](http://github.com/openresty/memc-nginx-module)
* [ngx_postgres](https://github.com/FRiCKLE/ngx_postgres)
* [ngx_redis2](http://github.com/openresty/redis2-nginx-module)
* [ngx_redis](http://wiki.nginx.org/HttpRedisModule)
* [ngx_proxy](http://nginx.org/en/docs/http/ngx_http_proxy_module.html)
* [ngx_fastcgi](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)

Almost any Nginx modules can be used with this ngx_lua module by means of
[ngx.location.capture](#ngxlocationcapture) or
[ngx.location.capture_multi](#ngxlocationcapture_multi) but it is
recommended to use those `lua-resty-*` libraries instead of creating
subrequests to access the Nginx upstream modules because the former is usually
much more flexible and memory-efficient.

The Lua interpreter (also known as "Lua State" or "LuaJIT VM instance") is
shared across all the requests in a single Nginx worker process to minimize
memory use. Request contexts are segregated using lightweight Lua coroutines.

Loaded Lua modules persist in the Nginx worker process level resulting in a
small memory footprint in Lua even when under heavy loads.

This module is plugged into Nginx's "http" subsystem so it can only speaks
downstream communication protocols in the HTTP family (HTTP 0.9/1.0/1.1/2.0,
WebSockets, etc...).  If you want to do generic TCP communications with the
downstream clients, then you should use the
[ngx_stream_lua](https://github.com/openresty/stream-lua-nginx-module#readme)
module instead, which offers a compatible Lua API.

[Back to TOC](#table-of-contents)

Typical Uses
============

Just to name a few:

* Mashup'ing and processing outputs of various Nginx upstream outputs (proxy, drizzle, postgres, redis, memcached, and etc) in Lua,
* doing arbitrarily complex access control and security checks in Lua before requests actually reach the upstream backends,
* manipulating response headers in an arbitrary way (by Lua)
* fetching backend information from external storage backends (like redis, memcached, mysql, postgresql) and use that information to choose which upstream backend to access on-the-fly,
* coding up arbitrarily complex web applications in a content handler using synchronous but still non-blocking access to the database backends and other storage,
* doing very complex URL dispatch in Lua at rewrite phase,
* using Lua to implement advanced caching mechanism for Nginx's subrequests and arbitrary locations.

The possibilities are unlimited as the module allows bringing together various
elements within Nginx as well as exposing the power of the Lua language to the
user. The module provides the full flexibility of scripting while offering
performance levels comparable with native C language programs both in terms of
CPU time as well as memory footprint thanks to LuaJIT 2.x.

Other scripting language implementations typically struggle to match this
performance level.

[Back to TOC](#table-of-contents)

Nginx Compatibility
===================

The latest version of this module is compatible with the following versions of Nginx:

* 1.19.x  (last tested: 1.19.3)
* 1.17.x  (last tested: 1.17.8)
* 1.15.x  (last tested: 1.15.8)
* 1.14.x
* 1.13.x  (last tested: 1.13.6)
* 1.12.x
* 1.11.x  (last tested: 1.11.2)
* 1.10.x
* 1.9.x (last tested: 1.9.15)
* 1.8.x
* 1.7.x (last tested: 1.7.10)
* 1.6.x

Nginx cores older than 1.6.0 (exclusive) are *not* supported.

[Back to TOC](#table-of-contents)

Installation
============

It is *highly* recommended to use [OpenResty releases](https://openresty.org)
which bundle Nginx, ngx_lua (this module), LuaJIT, as well as other powerful
companion Nginx modules and Lua libraries.

It is discouraged to build this module with Nginx yourself since it is tricky
to set up exactly right.

Note that Nginx, LuaJIT, and OpenSSL official releases have various limitations
and long standing bugs that can cause some of this module's features to be
disabled, not work properly, or run slower. Official OpenResty releases are
recommended because they bundle [OpenResty's optimized LuaJIT 2.1 fork](https://github.com/openresty/luajit2) and
[Nginx/OpenSSL
patches](https://github.com/openresty/openresty/tree/master/patches).

Alternatively, ngx_lua can be manually compiled into Nginx:

1. LuaJIT can be downloaded from the [latest release of OpenResty's LuaJIT fork](https://github.com/openresty/luajit2/releases). The official LuaJIT 2.x releases are also supported, although performance will be significantly lower for reasons elaborated above
1. Download the latest version of the ngx_devel_kit (NDK) module [HERE](https://github.com/simplresty/ngx_devel_kit/tags)
1. Download the latest version of ngx_lua [HERE](https://github.com/openresty/lua-nginx-module/tags)
1. Download the latest supported version of Nginx [HERE](https://nginx.org/) (See [Nginx Compatibility](#nginx-compatibility))
1. Download the latest version of the lua-resty-core [HERE](https://github.com/openresty/lua-resty-core)
1. Download the latest version of the lua-resty-lrucache [HERE](https://github.com/openresty/lua-resty-lrucache)

Build the source with this module:

```bash

 wget 'https://openresty.org/download/nginx-1.19.3.tar.gz'
 tar -xzvf nginx-1.19.3.tar.gz
 cd nginx-1.19.3/

 # tell nginx's build system where to find LuaJIT 2.0:
 export LUAJIT_LIB=/path/to/luajit/lib
 export LUAJIT_INC=/path/to/luajit/include/luajit-2.0

 # tell nginx's build system where to find LuaJIT 2.1:
 export LUAJIT_LIB=/path/to/luajit/lib
 export LUAJIT_INC=/path/to/luajit/include/luajit-2.1

 # Here we assume Nginx is to be installed under /opt/nginx/.
 ./configure --prefix=/opt/nginx \
         --with-ld-opt="-Wl,-rpath,/path/to/luajit/lib" \
         --add-module=/path/to/ngx_devel_kit \
         --add-module=/path/to/lua-nginx-module

 # Note that you may also want to add `./configure` options which are used in your
 # current nginx build.
 # You can get usually those options using command nginx -V

 # you can change the parallelism number 2 below to fit the number of spare CPU cores in your
 # machine.
 make -j2
 make install

 # Note that this version of lug-nginx-module not allow to set `lua_load_resty_core off;` any more.
 # So, you have to install `lua-resty-core` and `lua-resty-lrucache` manually as below.

 cd lua-resty-core
 make install PREFIX=/opt/nginx
 cd lua-resty-lrucache
 make install PREFIX=/opt/nginx

 # add necessary `lua_package_path` directive to `nginx.conf`, in the http context

 lua_package_path "/opt/nginx/lib/lua/?.lua;;";
```

[Back to TOC](#table-of-contents)

Building as a dynamic module
----------------------------

Starting from NGINX 1.9.11, you can also compile this module as a dynamic module, by using the `--add-dynamic-module=PATH` option instead of `--add-module=PATH` on the
`./configure` command line above. And then you can explicitly load the module in your `nginx.conf` via the [load_module](https://nginx.org/en/docs/ngx_core_module.html#load_module)
directive, for example,

```nginx

 load_module /path/to/modules/ndk_http_module.so;  # assuming NDK is built as a dynamic module too
 load_module /path/to/modules/ngx_http_lua_module.so;
```

[Back to TOC](#table-of-contents)

C Macro Configurations
----------------------

While building this module either via OpenResty or with the Nginx core, you can define the following C macros via the C compiler options:

* `NGX_LUA_USE_ASSERT`
	When defined, will enable assertions in the ngx_lua C code base. Recommended for debugging or testing builds. It can introduce some (small) runtime overhead when enabled. This macro was first introduced in the `v0.9.10` release.
* `NGX_LUA_ABORT_AT_PANIC`
	When the LuaJIT VM panics, ngx_lua will instruct the current nginx worker process to quit gracefully by default. By specifying this C macro, ngx_lua will abort the current nginx worker process (which usually result in a core dump file) immediately. This option is useful for debugging VM panics. This option was first introduced in the `v0.9.8` release.

To enable one or more of these macros, just pass extra C compiler options to the `./configure` script of either Nginx or OpenResty. For instance,


    ./configure --with-cc-opt="-DNGX_LUA_USE_ASSERT -DNGX_LUA_ABORT_AT_PANIC"


[Back to TOC](#table-of-contents)

Community
=========

[Back to TOC](#table-of-contents)

English Mailing List
--------------------

The [openresty-en](https://groups.google.com/group/openresty-en) mailing list is for English speakers.

[Back to TOC](#table-of-contents)

Chinese Mailing List
--------------------

The [openresty](https://groups.google.com/group/openresty) mailing list is for Chinese speakers.

[Back to TOC](#table-of-contents)

Code Repository
===============

The code repository of this project is hosted on GitHub at
[openresty/lua-nginx-module](https://github.com/openresty/lua-nginx-module).

[Back to TOC](#table-of-contents)

Bugs and Patches
================

Please submit bug reports, wishlists, or patches by

1. creating a ticket on the [GitHub Issue Tracker](https://github.com/openresty/lua-nginx-module/issues),
1. or posting to the [OpenResty community](#community).

[Back to TOC](#table-of-contents)

LuaJIT bytecode support
=======================

Watch YouTube video "[Measure Execution Time of Lua Code Correctly in OpenResty](https://youtu.be/VkRYW_qLoME)"

[![Precompile Lua Modules into LuaJIT Bytecode to Speedup OpenResty Startup](https://img.youtube.com/vi/EP7c0BM2yNo/0.jpg)](https://youtu.be/EP7c0BM2yNo)

As from the `v0.5.0rc32` release, all `*_by_lua_file` configure directives (such as [content_by_lua_file](#content_by_lua_file)) support loading LuaJIT 2.0/2.1 raw bytecode files directly:

```bash

 /path/to/luajit/bin/luajit -b /path/to/input_file.lua /path/to/output_file.ljbc
```

The `-bg` option can be used to include debug information in the LuaJIT bytecode file:

```bash

 /path/to/luajit/bin/luajit -bg /path/to/input_file.lua /path/to/output_file.ljbc
```

Please refer to the official LuaJIT documentation on the `-b` option for more details:

<https://luajit.org/running.html#opt_b>

Note that the bytecode files generated by LuaJIT 2.1 is *not* compatible with
LuaJIT 2.0, and vice versa. The support for LuaJIT 2.1 bytecode was first added
in ngx_lua v0.9.3.

Attempts to load standard Lua 5.1 bytecode files into ngx_lua instances linked
to LuaJIT 2.0/2.1 (or vice versa) will result in an Nginx error message such as
the one below:


    [error] 13909#0: *1 failed to load Lua inlined code: bad byte-code header in /path/to/test_file.luac


Loading bytecode files via the Lua primitives like `require` and
`dofile` should always work as expected.

[Back to TOC](#table-of-contents)

System Environment Variable Support
===================================

If you want to access the system environment variable, say, `foo`, in Lua via the standard Lua API [os.getenv](https://www.lua.org/manual/5.1/manual.html#pdf-os.getenv), then you should also list this environment variable name in your `nginx.conf` file via the [env directive](https://nginx.org/en/docs/ngx_core_module.html#env). For example,

```nginx

 env foo;
```

[Back to TOC](#table-of-contents)

HTTP 1.0 support
================

The HTTP 1.0 protocol does not support chunked output and requires an explicit `Content-Length` header when the response body is not empty in order to support the HTTP 1.0 keep-alive.
So when a HTTP 1.0 request is made and the [lua_http10_buffering](#lua_http10_buffering) directive is turned `on`, ngx_lua will buffer the
output of [ngx.say](#ngxsay) and [ngx.print](#ngxprint) calls and also postpone sending response headers until all the response body output is received.
At that time ngx_lua can calculate the total length of the body and construct a proper `Content-Length` header to return to the HTTP 1.0 client.
If the `Content-Length` response header is set in the running Lua code, however, this buffering will be disabled even if the [lua_http10_buffering](#lua_http10_buffering) directive is turned `on`.

For large streaming output responses, it is important to disable the [lua_http10_buffering](#lua_http10_buffering) directive to minimise memory usage.

Note that common HTTP benchmark tools such as `ab` and `http_load` issue HTTP 1.0 requests by default.
To force `curl` to send HTTP 1.0 requests, use the `-0` option.

[Back to TOC](#table-of-contents)

Statically Linking Pure Lua Modules
===================================

With LuaJIT 2.x, it is possible to statically link the bytecode of pure Lua
modules into the Nginx executable.

You can use the `luajit` executable to compile `.lua` Lua
module files to `.o` object files containing the exported bytecode
data, and then link the `.o` files directly in your Nginx build.

Below is a trivial example to demonstrate this. Consider that we have the following `.lua` file named `foo.lua`:

```lua

 -- foo.lua
 local _M = {}

 function _M.go()
     print("Hello from foo")
 end

 return _M
```

And then we compile this `.lua` file to `foo.o` file:

```bash

 /path/to/luajit/bin/luajit -bg foo.lua foo.o
```

What matters here is the name of the `.lua` file, which determines how you use this module later on the Lua land. The file name `foo.o` does not matter at all except the `.o` file extension (which tells `luajit` what output format is used). If you want to strip the Lua debug information from the resulting bytecode, you can just specify the `-b` option above instead of `-bg`.

Then when building Nginx or OpenResty, pass the `--with-ld-opt="foo.o"` option to the `./configure` script:

```bash

 ./configure --with-ld-opt="/path/to/foo.o" ...
```

Finally, you can just do the following in any Lua code run by ngx_lua:

```lua

 local foo = require "foo"
 foo.go()
```

And this piece of code no longer depends on the external `foo.lua` file any more because it has already been compiled into the `nginx` executable.

If you want to use dot in the Lua module name when calling `require`, as in

```lua

 local foo = require "resty.foo"
```

then you need to rename the `foo.lua` file to `resty_foo.lua` before compiling it down to a `.o` file with the `luajit` command-line utility.

It is important to use exactly the same version of LuaJIT when compiling `.lua` files to `.o` files as building nginx + ngx_lua. This is because the LuaJIT bytecode format may be incompatible between different LuaJIT versions. When the bytecode format is incompatible, you will see a Lua runtime error saying that the Lua module is not found.

When you have multiple `.lua` files to compile and link, then just specify their `.o` files at the same time in the value of the `--with-ld-opt` option. For instance,

```bash

 ./configure --with-ld-opt="/path/to/foo.o /path/to/bar.o" ...
```

If you have too many `.o` files, then it might not be feasible to name them all in a single command. In this case, you can build a static library (or archive) for your `.o` files, as in

```bash

 ar rcus libmyluafiles.a *.o
```

then you can link the `myluafiles` archive as a whole to your nginx executable:

```bash

 ./configure \
     --with-ld-opt="-L/path/to/lib -Wl,--whole-archive -lmyluafiles -Wl,--no-whole-archive"
```

where `/path/to/lib` is the path of the directory containing the `libmyluafiles.a` file. It should be noted that the linker option `--whole-archive` is required here because otherwise our archive will be skipped because no symbols in our archive are mentioned in the main parts of the nginx executable.

[Back to TOC](#table-of-contents)

Data Sharing within an Nginx Worker
===================================

To globally share data among all the requests handled by the same Nginx worker
process, encapsulate the shared data into a Lua module, use the Lua
`require` builtin to import the module, and then manipulate the
shared data in Lua. This works because required Lua modules are loaded only
once and all coroutines will share the same copy of the module (both its code
and data).

Note that the use of global Lua variables is *strongly discouraged*, as it may
lead to unexpected race conditions between concurrent requests.

Here is a small example on sharing data within an Nginx worker via a Lua module:

```lua

 -- mydata.lua
 local _M = {}

 local data = {
     dog = 3,
     cat = 4,
     pig = 5,
 }

 function _M.get_age(name)
     return data[name]
 end

 return _M
```

and then accessing it from `nginx.conf`:

```nginx

 location /lua {
     content_by_lua_block {
         local mydata = require "mydata"
         ngx.say(mydata.get_age("dog"))
     }
 }
```

The `mydata` module in this example will only be loaded and run on the first request to the location `/lua`,
and all subsequent requests to the same Nginx worker process will use the reloaded instance of the
module as well as the same copy of the data in it, until a `HUP` signal is sent to the Nginx master process to force a reload.
This data sharing technique is essential for high performance Lua applications based on this module.

Note that this data sharing is on a *per-worker* basis and not on a *per-server* basis. That is, when there are multiple Nginx worker processes under an Nginx master, data sharing cannot cross the process boundary between these workers.

It is usually recommended to share read-only data this way. You can also share changeable data among all the concurrent requests of each Nginx worker process as
long as there is *no* nonblocking I/O operations (including [ngx.sleep](#ngxsleep))
in the middle of your calculations. As long as you do not give the
control back to the Nginx event loop and ngx_lua's light thread
scheduler (even implicitly), there can never be any race conditions in
between. For this reason, always be very careful when you want to share changeable data on the
worker level. Buggy optimizations can easily lead to hard-to-debug
race conditions under load.

If server-wide data sharing is required, then use one or more of the following approaches:

1. Use the [ngx.shared.DICT](#ngxshareddict) API provided by this module.
1. Use only a single Nginx worker and a single server (this is however not recommended when there is a multi core CPU or multiple CPUs in a single machine).
1. Use data storage mechanisms such as `memcached`, `redis`, `MySQL` or `PostgreSQL`. [The OpenResty official releases](https://openresty.org) come with a set of companion Nginx modules and Lua libraries that provide interfaces with these data storage mechanisms.

[Back to TOC](#table-of-contents)

Known Issues
============

[Back to TOC](#table-of-contents)

TCP socket connect operation issues
-----------------------------------

The [tcpsock:connect](#tcpsockconnect) method may indicate `success` despite connection failures such as with `Connection Refused` errors.

However, later attempts to manipulate the cosocket object will fail and return the actual error status message generated by the failed connect operation.

This issue is due to limitations in the Nginx event model and only appears to affect Mac OS X.

[Back to TOC](#table-of-contents)

Lua Coroutine Yielding/Resuming
-------------------------------

* Because Lua's `dofile` and `require` builtins are currently implemented as C functions in LuaJIT 2.0/2.1, if the Lua file being loaded by `dofile` or `require` invokes [ngx.location.capture*](#ngxlocationcapture), [ngx.exec](#ngxexec), [ngx.exit](#ngxexit), or other API functions requiring yielding in the *top-level* scope of the Lua file, then the Lua error "attempt to yield across C-call boundary" will be raised. To avoid this, put these calls requiring yielding into your own Lua functions in the Lua file instead of the top-level scope of the file.

[Back to TOC](#table-of-contents)

Lua Variable Scope
------------------

Care must be taken when importing modules, and this form should be used:

```lua

 local xxx = require('xxx')
```

instead of the old deprecated form:

```lua

 require('xxx')
```

Here is the reason: by design, the global environment has exactly the same lifetime as the Nginx request handler associated with it. Each request handler has its own set of Lua global variables and that is the idea of request isolation. The Lua module is actually loaded by the first Nginx request handler and is cached by the `require()` built-in in the `package.loaded` table for later reference, and the `module()` builtin used by some Lua modules has the side effect of setting a global variable to the loaded module table. But this global variable will be cleared at the end of the request handler,  and every subsequent request handler all has its own (clean) global environment. So one will get Lua exception for accessing the `nil` value.

The use of Lua global variables is a generally inadvisable in the ngx_lua context as:

1. the misuse of Lua globals has detrimental side effects on concurrent requests when such variables should instead be local in scope,
1. Lua global variables require Lua table look-ups in the global environment which is computationally expensive, and
1. some Lua global variable references may include typing errors which make such difficult to debug.

It is therefore *highly* recommended to always declare such within an appropriate local scope instead.

```lua

 -- Avoid
 foo = 123
 -- Recommended
 local foo = 123

 -- Avoid
 function foo() return 123 end
 -- Recommended
 local function foo() return 123 end
```

To find all instances of Lua global variables in your Lua code, run the [lua-releng tool](https://github.com/openresty/nginx-devel-utils/blob/master/lua-releng) across all `.lua` source files:

    $ lua-releng
    Checking use of Lua global variables in file lib/foo/bar.lua ...
            1       [1489]  SETGLOBAL       7 -1    ; contains
            55      [1506]  GETGLOBAL       7 -3    ; setvar
            3       [1545]  GETGLOBAL       3 -4    ; varexpand

The output says that the line 1489 of file `lib/foo/bar.lua` writes to a global variable named `contains`, the line 1506 reads from the global variable `setvar`, and line 1545 reads the global `varexpand`.

This tool will guarantee that local variables in the Lua module functions are all declared with the `local` keyword, otherwise a runtime exception will be thrown. It prevents undesirable race conditions while accessing such variables. See [Data Sharing within an Nginx Worker](#data-sharing-within-an-nginx-worker) for the reasons behind this.

[Back to TOC](#table-of-contents)

Locations Configured by Subrequest Directives of Other Modules
--------------------------------------------------------------

The [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi) directives cannot capture locations that include the [add_before_body](http://nginx.org/en/docs/http/ngx_http_addition_module.html#add_before_body), [add_after_body](http://nginx.org/en/docs/http/ngx_http_addition_module.html#add_after_body), [auth_request](https://nginx.org/en/docs/http/ngx_http_auth_request_module.html#auth_request), [echo_location](http://github.com/openresty/echo-nginx-module#echo_location), [echo_location_async](http://github.com/openresty/echo-nginx-module#echo_location_async), [echo_subrequest](http://github.com/openresty/echo-nginx-module#echo_subrequest), or [echo_subrequest_async](http://github.com/openresty/echo-nginx-module#echo_subrequest_async) directives.

```nginx

 location /foo {
     content_by_lua_block {
         res = ngx.location.capture("/bar")
     }
 }
 location /bar {
     echo_location /blah;
 }
 location /blah {
     echo "Success!";
 }
```

```nginx

 $ curl -i http://example.com/foo
```

will not work as expected.

[Back to TOC](#table-of-contents)

Cosockets Not Available Everywhere
----------------------------------

Due to internal limitations in the Nginx core, the cosocket API is disabled in the following contexts: [set_by_lua*](#set_by_lua), [log_by_lua*](#log_by_lua), [header_filter_by_lua*](#header_filter_by_lua), and [body_filter_by_lua](#body_filter_by_lua).

The cosockets are currently also disabled in the [init_by_lua*](#init_by_lua) and [init_worker_by_lua*](#init_worker_by_lua) directive contexts but we may add support for these contexts in the future because there is no limitation in the Nginx core (or the limitation might be worked around).

There exists a workaround, however, when the original context does *not* need to wait for the cosocket results. That is, creating a zero-delay timer via the [ngx.timer.at](#ngxtimerat) API and do the cosocket results in the timer handler, which runs asynchronously as to the original context creating the timer.

[Back to TOC](#table-of-contents)

Special Escaping Sequences
--------------------------

**NOTE** Following the `v0.9.17` release, this pitfall can be avoided by using the `*_by_lua_block {}` configuration directives.

PCRE sequences such as `\d`, `\s`, or `\w`, require special attention because in string literals, the backslash character, `\`, is stripped out by both the Lua language parser and by the Nginx config file parser before processing if not within a `*_by_lua_block {}` directive. So the following snippet will not work as expected:

```nginx

 # nginx.conf
 ? location /test {
 ?     content_by_lua '
 ?         local regex = "\d+"  -- THIS IS WRONG OUTSIDE OF A *_by_lua_block DIRECTIVE
 ?         local m = ngx.re.match("hello, 1234", regex)
 ?         if m then ngx.say(m[0]) else ngx.say("not matched!") end
 ?     ';
 ? }
 # evaluates to "not matched!"
```

To avoid this, *double* escape the backslash:

```nginx

 # nginx.conf
 location /test {
     content_by_lua '
         local regex = "\\\\d+"
         local m = ngx.re.match("hello, 1234", regex)
         if m then ngx.say(m[0]) else ngx.say("not matched!") end
     ';
 }
 # evaluates to "1234"
```

Here, `\\\\d+` is stripped down to `\\d+` by the Nginx config file parser and this is further stripped down to `\d+` by the Lua language parser before running.

Alternatively, the regex pattern can be presented as a long-bracketed Lua string literal by encasing it in "long brackets", `[[...]]`, in which case backslashes have to only be escaped once for the Nginx config file parser.

```nginx

 # nginx.conf
 location /test {
     content_by_lua '
         local regex = [[\\d+]]
         local m = ngx.re.match("hello, 1234", regex)
         if m then ngx.say(m[0]) else ngx.say("not matched!") end
     ';
 }
 # evaluates to "1234"
```

Here, `[[\\d+]]` is stripped down to `[[\d+]]` by the Nginx config file parser and this is processed correctly.

Note that a longer from of the long bracket, `[=[...]=]`, may be required if the regex pattern contains `[...]` sequences.
The `[=[...]=]` form may be used as the default form if desired.

```nginx

 # nginx.conf
 location /test {
     content_by_lua '
         local regex = [=[[0-9]+]=]
         local m = ngx.re.match("hello, 1234", regex)
         if m then ngx.say(m[0]) else ngx.say("not matched!") end
     ';
 }
 # evaluates to "1234"
```

An alternative approach to escaping PCRE sequences is to ensure that Lua code is placed in external script files and executed using the various `*_by_lua_file` directives.
With this approach, the backslashes are only stripped by the Lua language parser and therefore only need to be escaped once each.

```lua

 -- test.lua
 local regex = "\\d+"
 local m = ngx.re.match("hello, 1234", regex)
 if m then ngx.say(m[0]) else ngx.say("not matched!") end
 -- evaluates to "1234"
```

Within external script files, PCRE sequences presented as long-bracketed Lua string literals do not require modification.

```lua

 -- test.lua
 local regex = [[\d+]]
 local m = ngx.re.match("hello, 1234", regex)
 if m then ngx.say(m[0]) else ngx.say("not matched!") end
 -- evaluates to "1234"
```

As noted earlier, PCRE sequences presented within `*_by_lua_block {}` directives (available following the `v0.9.17` release) do not require modification.

```nginx

 # nginx.conf
 location /test {
     content_by_lua_block {
         local regex = [[\d+]]
         local m = ngx.re.match("hello, 1234", regex)
         if m then ngx.say(m[0]) else ngx.say("not matched!") end
     }
 }
 # evaluates to "1234"
```

**NOTE** You are recommended to use `by_lua_file` when the Lua code is very long.

[Back to TOC](#table-of-contents)

Mixing with SSI Not Supported
-----------------------------

Mixing SSI with ngx_lua in the same Nginx request is not supported at all. Just use ngx_lua exclusively. Everything you can do with SSI can be done atop ngx_lua anyway and it can be more efficient when using ngx_lua.

[Back to TOC](#table-of-contents)

SPDY Mode Not Fully Supported
-----------------------------

Certain Lua APIs provided by ngx_lua do not work in Nginx's SPDY mode yet: [ngx.location.capture](#ngxlocationcapture), [ngx.location.capture_multi](#ngxlocationcapture_multi), and [ngx.req.socket](#ngxreqsocket).

[Back to TOC](#table-of-contents)

Missing data on short circuited requests
----------------------------------------

Nginx may terminate a request early with (at least):

* 400 (Bad Request)
* 405 (Not Allowed)
* 408 (Request Timeout)
* 413 (Request Entity Too Large)
* 414 (Request URI Too Large)
* 494 (Request Headers Too Large)
* 499 (Client Closed Request)
* 500 (Internal Server Error)
* 501 (Not Implemented)

This means that phases that normally run are skipped, such as the rewrite or
access phase. This also means that later phases that are run regardless, e.g.
[log_by_lua](#log_by_lua), will not have access to information that is normally set in those
phases.

[Back to TOC](#table-of-contents)

TODO
====

* cosocket: implement LuaSocket's unconnected UDP API.
* cosocket: add support in the context of [init_by_lua*](#init_by_lua).
* cosocket: implement the `bind()` method for stream-typed cosockets.
* cosocket: review and merge aviramc's [patch](https://github.com/openresty/lua-nginx-module/pull/290) for adding the `bsdrecv` method.
* cosocket: add configure options for different strategies of handling the cosocket connection exceeding in the pools.
* review and apply vadim-pavlov's patch for [ngx.location.capture](#ngxlocationcapture)'s `extra_headers` option
* use `ngx_hash_t` to optimize the built-in header look-up process for [ngx.req.set_header](#ngxreqset_header), and etc.
* add `ignore_resp_headers`, `ignore_resp_body`, and `ignore_resp` options to [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi) methods, to allow micro performance tuning on the user side.
* add automatic Lua code time slicing support by yielding and resuming the Lua VM actively via Lua's debug hooks.
* add `stat` mode similar to [mod_lua](https://httpd.apache.org/docs/trunk/mod/mod_lua.html).

[Back to TOC](#table-of-contents)

Changes
=======

The changes made in every release of this module are listed in the change logs of the OpenResty bundle:

<https://openresty.org/#Changes>

[Back to TOC](#table-of-contents)

Test Suite
==========

The following dependencies are required to run the test suite:

* Nginx version >= 1.4.2

* Perl modules:
	* Test::Nginx: <https://github.com/openresty/test-nginx>

* Nginx modules:
	* [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit)
	* [ngx_set_misc](https://github.com/openresty/set-misc-nginx-module)
	* [ngx_auth_request](http://mdounin.ru/files/ngx_http_auth_request_module-0.2.tar.gz) (this is not needed if you're using Nginx 1.5.4+.
	* [ngx_echo](https://github.com/openresty/echo-nginx-module)
	* [ngx_memc](https://github.com/openresty/memc-nginx-module)
	* [ngx_srcache](https://github.com/openresty/srcache-nginx-module)
	* ngx_lua (i.e., this module)
	* [ngx_lua_upstream](https://github.com/openresty/lua-upstream-nginx-module)
	* [ngx_headers_more](https://github.com/openresty/headers-more-nginx-module)
	* [ngx_drizzle](https://github.com/openresty/drizzle-nginx-module)
	* [ngx_rds_json](https://github.com/openresty/rds-json-nginx-module)
	* [ngx_coolkit](https://github.com/FRiCKLE/ngx_coolkit)
	* [ngx_redis2](https://github.com/openresty/redis2-nginx-module)

The order in which these modules are added during configuration is important because the position of any filter module in the
filtering chain determines the final output, for example. The correct adding order is shown above.

* 3rd-party Lua libraries:
	* [lua-cjson](http://www.kyne.com.au/~mark/software/lua-cjson.php)

* Applications:
	* mysql: create database 'ngx_test', grant all privileges to user 'ngx_test', password is 'ngx_test'
	* memcached: listening on the default port, 11211.
	* redis: listening on the default port, 6379.

See also the [developer build script](https://github.com/openresty/lua-nginx-module/blob/master/util/build.sh) for more details on setting up the testing environment.

To run the whole test suite in the default testing mode:

    cd /path/to/lua-nginx-module
    export PATH=/path/to/your/nginx/sbin:$PATH
    prove -I/path/to/test-nginx/lib -r t


To run specific test files:

    cd /path/to/lua-nginx-module
    export PATH=/path/to/your/nginx/sbin:$PATH
    prove -I/path/to/test-nginx/lib t/002-content.t t/003-errors.t


To run a specific test block in a particular test file, add the line `--- ONLY` to the test block you want to run, and then use the `prove` utility to run that `.t` file.

There are also various testing modes based on mockeagain, valgrind, and etc. Refer to the [Test::Nginx documentation](https://search.cpan.org/perldoc?Test::Nginx) for more details for various advanced testing modes. See also the test reports for the Nginx test cluster running on Amazon EC2: <https://qa.openresty.org>.

[Back to TOC](#table-of-contents)

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2009-2017, by Xiaozhe Wang (chaoslawful) <chaoslawful@gmail.com>.

Copyright (C) 2009-2019, by Yichun "agentzh" Zhang (章亦春) <agentzh@gmail.com>, OpenResty Inc.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

[Back to TOC](#table-of-contents)

See Also
========

Blog posts:

* [Introduction to Lua-Land CPU Flame Graphs](https://blog.openresty.com/en/lua-cpu-flame-graph/?src=gh_ngxlua)
* [How OpenResty and Nginx Allocate and Manage Memory](https://blog.openresty.com/en//how-or-alloc-mem?src=gh_ngxlua)
* [How OpenResty and Nginx Shared Memory Zones Consume RAM](https://blog.openresty.com/en/how-nginx-shm-consume-ram/?src=gh_ngxlua)
* [Memory Fragmentation in OpenResty and Nginx's Shared Memory Zones](https://blog.openresty.com/en/nginx-shm-frag/?src=gh_ngxlua)

Other related modules and libraries:

* [ngx_stream_lua_module](https://github.com/openresty/stream-lua-nginx-module#readme) for an official port of this module for the Nginx "stream" subsystem (doing generic downstream TCP communications).
* [lua-resty-memcached](https://github.com/openresty/lua-resty-memcached) library based on ngx_lua cosocket.
* [lua-resty-redis](https://github.com/openresty/lua-resty-redis) library based on ngx_lua cosocket.
* [lua-resty-mysql](https://github.com/openresty/lua-resty-mysql) library based on ngx_lua cosocket.
* [lua-resty-upload](https://github.com/openresty/lua-resty-upload) library based on ngx_lua cosocket.
* [lua-resty-dns](https://github.com/openresty/lua-resty-dns) library based on ngx_lua cosocket.
* [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket) library for both WebSocket server and client, based on ngx_lua cosocket.
* [lua-resty-string](https://github.com/openresty/lua-resty-string) library based on [LuaJIT FFI](https://luajit.org/ext_ffi.html).
* [lua-resty-lock](https://github.com/openresty/lua-resty-lock) library for a nonblocking simple lock API.
* [lua-resty-cookie](https://github.com/cloudflare/lua-resty-cookie) library for HTTP cookie manipulation.
* [Routing requests to different MySQL queries based on URI arguments](https://openresty.org/#RoutingMySQLQueriesBasedOnURIArgs)
* [Dynamic Routing Based on Redis and Lua](https://openresty.org/#DynamicRoutingBasedOnRedis)
* [Using LuaRocks with ngx_lua](https://openresty.org/#UsingLuaRocks)
* [Introduction to ngx_lua](https://github.com/openresty/lua-nginx-module/wiki/Introduction)
* [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit)
* [echo-nginx-module](http://github.com/openresty/echo-nginx-module)
* [drizzle-nginx-module](http://github.com/openresty/drizzle-nginx-module)
* [postgres-nginx-module](https://github.com/FRiCKLE/ngx_postgres)
* [memc-nginx-module](http://github.com/openresty/memc-nginx-module)
* [The OpenResty bundle](https://openresty.org)
* [Nginx Systemtap Toolkit](https://github.com/openresty/nginx-systemtap-toolkit)

[Back to TOC](#table-of-contents)

Directives
==========

* [lua_load_resty_core](#lua_load_resty_core)
* [lua_capture_error_log](#lua_capture_error_log)
* [lua_use_default_type](#lua_use_default_type)
* [lua_malloc_trim](#lua_malloc_trim)
* [lua_code_cache](#lua_code_cache)
* [lua_thread_cache_max_entries](#lua_thread_cache_max_entries)
* [lua_regex_cache_max_entries](#lua_regex_cache_max_entries)
* [lua_regex_match_limit](#lua_regex_match_limit)
* [lua_package_path](#lua_package_path)
* [lua_package_cpath](#lua_package_cpath)
* [init_by_lua](#init_by_lua)
* [init_by_lua_block](#init_by_lua_block)
* [init_by_lua_file](#init_by_lua_file)
* [init_worker_by_lua](#init_worker_by_lua)
* [init_worker_by_lua_block](#init_worker_by_lua_block)
* [init_worker_by_lua_file](#init_worker_by_lua_file)
* [exit_worker_by_lua_block](#exit_worker_by_lua_block)
* [exit_worker_by_lua_file](#exit_worker_by_lua_file)
* [set_by_lua](#set_by_lua)
* [set_by_lua_block](#set_by_lua_block)
* [set_by_lua_file](#set_by_lua_file)
* [content_by_lua](#content_by_lua)
* [content_by_lua_block](#content_by_lua_block)
* [content_by_lua_file](#content_by_lua_file)
* [server_rewrite_by_lua_block](#server_rewrite_by_lua_block)
* [server_rewrite_by_lua_file](#server_rewrite_by_lua_file)
* [rewrite_by_lua](#rewrite_by_lua)
* [rewrite_by_lua_block](#rewrite_by_lua_block)
* [rewrite_by_lua_file](#rewrite_by_lua_file)
* [access_by_lua](#access_by_lua)
* [access_by_lua_block](#access_by_lua_block)
* [access_by_lua_file](#access_by_lua_file)
* [header_filter_by_lua](#header_filter_by_lua)
* [header_filter_by_lua_block](#header_filter_by_lua_block)
* [header_filter_by_lua_file](#header_filter_by_lua_file)
* [body_filter_by_lua](#body_filter_by_lua)
* [body_filter_by_lua_block](#body_filter_by_lua_block)
* [body_filter_by_lua_file](#body_filter_by_lua_file)
* [log_by_lua](#log_by_lua)
* [log_by_lua_block](#log_by_lua_block)
* [log_by_lua_file](#log_by_lua_file)
* [balancer_by_lua_block](#balancer_by_lua_block)
* [balancer_by_lua_file](#balancer_by_lua_file)
* [lua_need_request_body](#lua_need_request_body)
* [ssl_client_hello_by_lua_block](#ssl_client_hello_by_lua_block)
* [ssl_client_hello_by_lua_file](#ssl_client_hello_by_lua_file)
* [ssl_certificate_by_lua_block](#ssl_certificate_by_lua_block)
* [ssl_certificate_by_lua_file](#ssl_certificate_by_lua_file)
* [ssl_session_fetch_by_lua_block](#ssl_session_fetch_by_lua_block)
* [ssl_session_fetch_by_lua_file](#ssl_session_fetch_by_lua_file)
* [ssl_session_store_by_lua_block](#ssl_session_store_by_lua_block)
* [ssl_session_store_by_lua_file](#ssl_session_store_by_lua_file)
* [lua_shared_dict](#lua_shared_dict)
* [lua_socket_connect_timeout](#lua_socket_connect_timeout)
* [lua_socket_send_timeout](#lua_socket_send_timeout)
* [lua_socket_send_lowat](#lua_socket_send_lowat)
* [lua_socket_read_timeout](#lua_socket_read_timeout)
* [lua_socket_buffer_size](#lua_socket_buffer_size)
* [lua_socket_pool_size](#lua_socket_pool_size)
* [lua_socket_keepalive_timeout](#lua_socket_keepalive_timeout)
* [lua_socket_log_errors](#lua_socket_log_errors)
* [lua_ssl_ciphers](#lua_ssl_ciphers)
* [lua_ssl_crl](#lua_ssl_crl)
* [lua_ssl_protocols](#lua_ssl_protocols)
* [lua_ssl_trusted_certificate](#lua_ssl_trusted_certificate)
* [lua_ssl_verify_depth](#lua_ssl_verify_depth)
* [lua_ssl_conf_command](#lua_ssl_conf_command)
* [lua_http10_buffering](#lua_http10_buffering)
* [rewrite_by_lua_no_postpone](#rewrite_by_lua_no_postpone)
* [access_by_lua_no_postpone](#access_by_lua_no_postpone)
* [lua_transform_underscores_in_response_headers](#lua_transform_underscores_in_response_headers)
* [lua_check_client_abort](#lua_check_client_abort)
* [lua_max_pending_timers](#lua_max_pending_timers)
* [lua_max_running_timers](#lua_max_running_timers)
* [lua_sa_restart](#lua_sa_restart)
* [lua_worker_thread_vm_pool_size](#lua_worker_thread_vm_pool_size)


The basic building blocks of scripting Nginx with Lua are directives. Directives are used to specify when the user Lua code is run and
how the result will be used. Below is a diagram showing the order in which directives are executed.

![Lua Nginx Modules Directives](https://cloud.githubusercontent.com/assets/2137369/15272097/77d1c09e-1a37-11e6-97ef-d9767035fc3e.png)

[Back to TOC](#table-of-contents)

lua_load_resty_core
-------------------

**syntax:** *lua_load_resty_core on|off*

**default:** *lua_load_resty_core on*

**context:** *http*

This directive is deprecated since the `v0.10.16` release of this
module. The `resty.core` module from
[lua-resty-core](https://github.com/openresty/lua-resty-core) is now mandatorily
loaded during the Lua VM initialization. Specifying this directive will have no
effect.

This directive was first introduced in the `v0.10.15` release and
used to optionally load the `resty.core` module.

[Back to TOC](#directives)

lua_capture_error_log
---------------------

**syntax:** *lua_capture_error_log size*

**default:** *none*

**context:** *http*

Enables a buffer of the specified `size` for capturing all the Nginx error log message data (not just those produced
by this module or the Nginx http subsystem, but everything) without touching files or disks.

You can use units like `k` and `m` in the `size` value, as in

```nginx

 lua_capture_error_log 100k;
```

As a rule of thumb, a 4KB buffer can usually hold about 20 typical error log messages. So do the maths!

This buffer never grows. If it is full, new error log messages will replace the oldest ones in the buffer.

The size of the buffer must be bigger than the maximum length of a single error log message (which is 4K in OpenResty and 2K in stock NGINX).

You can read the messages in the buffer on the Lua land via the
[get_logs()](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/errlog.md#get_logs)
function of the
[ngx.errlog](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/errlog.md#readme)
module of the [lua-resty-core](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/errlog.md#readme)
library. This Lua API function will return the captured error log messages and
also remove these already read from the global capturing buffer, making room
for any new error log data. For this reason, the user should not configure this
buffer to be too big if the user read the buffered error log data fast enough.

Note that the log level specified in the standard [error_log](https://nginx.org/r/error_log) directive
*does* have effect on this capturing facility. It only captures log
messages of a level no lower than the specified log level in the [error_log](https://nginx.org/r/error_log) directive.
The user can still choose to set an even higher filtering log level on the fly via the Lua API function
[errlog.set_filter_level](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/errlog.md#set_filter_level).
So it is more flexible than the static [error_log](https://nginx.org/r/error_log) directive.

It is worth noting that there is no way to capture the debugging logs
without building OpenResty or Nginx with the `./configure`
option `--with-debug`. And enabling debugging logs is
strongly discouraged in production builds due to high overhead.

This directive was first introduced in the `v0.10.9` release.

[Back to TOC](#directives)

lua_use_default_type
--------------------

**syntax:** *lua_use_default_type on | off*

**default:** *lua_use_default_type on*

**context:** *http, server, location, location if*

Specifies whether to use the MIME type specified by the [default_type](https://nginx.org/en/docs/http/ngx_http_core_module.html#default_type) directive for the default value of the `Content-Type` response header. Deactivate this directive if a default `Content-Type` response header for Lua request handlers is not desired.

This directive is turned on by default.

This directive was first introduced in the `v0.9.1` release.

[Back to TOC](#directives)

lua_malloc_trim
---------------

**syntax:** *lua_malloc_trim &lt;request-count&gt;*

**default:** *lua_malloc_trim 1000*

**context:** *http*

Asks the underlying `libc` runtime library to release its cached free memory back to the operating system every
`N` requests processed by the Nginx core. By default, `N` is 1000. You can configure the request count
by using your own numbers. Smaller numbers mean more frequent releases, which may introduce higher CPU time consumption and
smaller memory footprint while larger numbers usually lead to less CPU time overhead and relatively larger memory footprint.
Just tune the number for your own use cases.

Configuring the argument to `0` essentially turns off the periodical memory trimming altogether.

```nginx

 lua_malloc_trim 0;  # turn off trimming completely
```

The current implementation uses an Nginx log phase handler to do the request counting. So the appearance of the
[log_subrequest on](https://nginx.org/en/docs/http/ngx_http_core_module.html#log_subrequest) directives in `nginx.conf`
may make the counting faster when subrequests are involved. By default, only "main requests" count.

Note that this directive does *not* affect the memory allocated by LuaJIT's own allocator based on the `mmap`
system call.

This directive was first introduced in the `v0.10.7` release.

[Back to TOC](#directives)

lua_code_cache
--------------
**syntax:** *lua_code_cache on | off*

**default:** *lua_code_cache on*

**context:** *http, server, location, location if*

Enables or disables the Lua code cache for Lua code in `*_by_lua_file` directives (like [set_by_lua_file](#set_by_lua_file) and
[content_by_lua_file](#content_by_lua_file)) and Lua modules.

When turning off, every request served by ngx_lua will run in a separate Lua VM instance, starting from the `0.9.3` release. So the Lua files referenced in [set_by_lua_file](#set_by_lua_file),
[content_by_lua_file](#content_by_lua_file), [access_by_lua_file](#access_by_lua_file),
and etc will not be cached
and all Lua modules used will be loaded from scratch. With this in place, developers can adopt an edit-and-refresh approach.

Please note however, that Lua code written inlined within nginx.conf
such as those specified by [set_by_lua](#set_by_lua), [content_by_lua](#content_by_lua),
[access_by_lua](#access_by_lua), and [rewrite_by_lua](#rewrite_by_lua) will not be updated when you edit the inlined Lua code in your `nginx.conf` file because only the Nginx config file parser can correctly parse the `nginx.conf`
file and the only way is to reload the config file
by sending a `HUP` signal or just to restart Nginx.

Even when the code cache is enabled, Lua files which are loaded by `dofile` or `loadfile`
in *_by_lua_file cannot be cached (unless you cache the results yourself). Usually you can either use the [init_by_lua](#init_by_lua)
or [init_by_lua_file](#init-by_lua_file) directives to load all such files or just make these Lua files true Lua modules
and load them via `require`.

The ngx_lua module does not support the `stat` mode available with the
Apache `mod_lua` module (yet).

Disabling the Lua code cache is strongly
discouraged for production use and should only be used during
development as it has a significant negative impact on overall performance. For example, the performance of a "hello world" Lua example can drop by an order of magnitude after disabling the Lua code cache.

[Back to TOC](#directives)

lua_thread_cache_max_entries
----------------------------

**syntax:** *lua_thread_cache_max_entries &lt;num&gt;*

**default:** *lua_thread_cache_max_entries 1024*

**context:** *http*

Specifies the maximum number of entries allowed in the worker process level lua thread object cache.

This cache recycles the lua thread GC objects among all our "light threads".

A zero value of `<num>` disables the cache.

Note that this feature requires OpenResty's LuaJIT with the new C API `lua_resetthread`.

This feature was first introduced in verson `v0.10.9`.

[Back to TOC](#directives)

lua_regex_cache_max_entries
---------------------------

**syntax:** *lua_regex_cache_max_entries &lt;num&gt;*

**default:** *lua_regex_cache_max_entries 1024*

**context:** *http*

Specifies the maximum number of entries allowed in the worker process level compiled regex cache.

The regular expressions used in [ngx.re.match](#ngxrematch), [ngx.re.gmatch](#ngxregmatch), [ngx.re.sub](#ngxresub), and [ngx.re.gsub](#ngxregsub) will be cached within this cache if the regex option `o` (i.e., compile-once flag) is specified.

The default number of entries allowed is 1024 and when this limit is reached, new regular expressions will not be cached (as if the `o` option was not specified) and there will be one, and only one, warning in the `error.log` file:


    2011/08/27 23:18:26 [warn] 31997#0: *1 lua exceeding regex cache max entries (1024), ...


If you are using the `ngx.re.*` implementation of [lua-resty-core](https://github.com/openresty/lua-resty-core) by loading the `resty.core.regex` module (or just the `resty.core` module), then an LRU cache is used for the regex cache being used here.

Do not activate the `o` option for regular expressions (and/or `replace` string arguments for [ngx.re.sub](#ngxresub) and [ngx.re.gsub](#ngxregsub)) that are generated *on the fly* and give rise to infinite variations to avoid hitting the specified limit.

[Back to TOC](#directives)

lua_regex_match_limit
---------------------

**syntax:** *lua_regex_match_limit &lt;num&gt;*

**default:** *lua_regex_match_limit 0*

**context:** *http*

Specifies the "match limit" used by the PCRE library when executing the [ngx.re API](#ngxrematch). To quote the PCRE manpage, "the limit ... has the effect of limiting the amount of backtracking that can take place."

When the limit is hit, the error string "pcre_exec() failed: -8" will be returned by the [ngx.re API](#ngxrematch) functions on the Lua land.

When setting the limit to 0, the default "match limit" when compiling the PCRE library is used. And this is the default value of this directive.

This directive was first introduced in the `v0.8.5` release.

[Back to TOC](#directives)

lua_package_path
----------------

**syntax:** *lua_package_path &lt;lua-style-path-str&gt;*

**default:** *The content of LUA_PATH environment variable or Lua's compiled-in defaults.*

**context:** *http*

Sets the Lua module search path used by scripts specified by [set_by_lua](#set_by_lua),
[content_by_lua](#content_by_lua) and others. The path string is in standard Lua path form, and `;;`
can be used to stand for the original search paths.

As from the `v0.5.0rc29` release, the special notation `$prefix` or `${prefix}` can be used in the search path string to indicate the path of the `server prefix` usually determined by the `-p PATH` command-line option while starting the Nginx server.

[Back to TOC](#directives)

lua_package_cpath
-----------------

**syntax:** *lua_package_cpath &lt;lua-style-cpath-str&gt;*

**default:** *The content of LUA_CPATH environment variable or Lua's compiled-in defaults.*

**context:** *http*

Sets the Lua C-module search path used by scripts specified by [set_by_lua](#set_by_lua),
[content_by_lua](#content_by_lua) and others. The cpath string is in standard Lua cpath form, and `;;`
can be used to stand for the original cpath.

As from the `v0.5.0rc29` release, the special notation `$prefix` or `${prefix}` can be used in the search path string to indicate the path of the `server prefix` usually determined by the `-p PATH` command-line option while starting the Nginx server.

[Back to TOC](#directives)

init_by_lua
-----------

**syntax:** *init_by_lua &lt;lua-script-str&gt;*

**context:** *http*

**phase:** *loading-config*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [init_by_lua_block](#init_by_lua_block) directive instead.

Similar to the [init_by_lua_block](#init_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 init_by_lua '
     print("I need no extra escaping here, for example: \r\nblah")
 '
```

This directive was first introduced in the `v0.5.5` release.

[Back to TOC](#directives)

init_by_lua_block
-----------------

**syntax:** *init_by_lua_block { lua-script }*

**context:** *http*

**phase:** *loading-config*


When Nginx receives the `HUP` signal and starts reloading the config file, the Lua VM will also be re-created and `init_by_lua_block` will run again on the new Lua VM. In case that the [lua_code_cache](#lua_code_cache) directive is turned off (default on), the `init_by_lua_block` handler will run upon every request because in this special mode a standalone Lua VM is always created for each request.

Usually you can pre-load Lua modules at server start-up by means of this hook and take advantage of modern operating systems' copy-on-write (COW) optimization. Here is an example for pre-loading Lua modules:

```nginx

 # this runs before forking out nginx worker processes:
 init_by_lua_block { require "cjson" }

 server {
     location = /api {
         content_by_lua_block {
             -- the following require() will just  return
             -- the already loaded module from package.loaded:
             ngx.say(require "cjson".encode{dog = 5, cat = 6})
         }
     }
 }
```

You can also initialize the [lua_shared_dict](#lua_shared_dict) shm storage at this phase. Here is an example for this:

```nginx

 lua_shared_dict dogs 1m;

 init_by_lua_block {
     local dogs = ngx.shared.dogs
     dogs:set("Tom", 56)
 }

 server {
     location = /api {
         content_by_lua_block {
             local dogs = ngx.shared.dogs
             ngx.say(dogs:get("Tom"))
         }
     }
 }
```

But note that, the [lua_shared_dict](#lua_shared_dict)'s shm storage will not be cleared through a config reload (via the `HUP` signal, for example). So if you do *not* want to re-initialize the shm storage in your `init_by_lua_block` code in this case, then you just need to set a custom flag in the shm storage and always check the flag in your `init_by_lua_block` code.

Because the Lua code in this context runs before Nginx forks its worker processes (if any), data or code loaded here will enjoy the [Copy-on-write (COW)](https://en.wikipedia.org/wiki/Copy-on-write) feature provided by many operating systems among all the worker processes, thus saving a lot of memory.

Do *not* initialize your own Lua global variables in this context because use of Lua global variables have performance penalties and can lead to global namespace pollution (see the [Lua Variable Scope](#lua-variable-scope) section for more details). The recommended way is to use proper [Lua module](https://www.lua.org/manual/5.1/manual.html#5.3) files (but do not use the standard Lua function [module()](https://www.lua.org/manual/5.1/manual.html#pdf-module) to define Lua modules because it pollutes the global namespace as well) and call [require()](https://www.lua.org/manual/5.1/manual.html#pdf-require) to load your own module files in `init_by_lua_block` or other contexts ([require()](https://www.lua.org/manual/5.1/manual.html#pdf-require) does cache the loaded Lua modules in the global `package.loaded` table in the Lua registry so your modules will only loaded once for the whole Lua VM instance).

Only a small set of the [Nginx API for Lua](#nginx-api-for-lua) is supported in this context:

* Logging APIs: [ngx.log](#ngxlog) and [print](#print),
* Shared Dictionary API: [ngx.shared.DICT](#ngxshareddict).

More Nginx APIs for Lua may be supported in this context upon future user requests.

Basically you can safely use Lua libraries that do blocking I/O in this very context because blocking the master process during server start-up is completely okay. Even the Nginx core does blocking I/O (at least on resolving upstream's host names) at the configure-loading phase.

You should be very careful about potential security vulnerabilities in your Lua code registered in this context because the Nginx master process is often run under the `root` account.

This directive was first introduced in the `v0.9.17` release.

See also the following blog posts for more details on OpenResty and Nginx's shared memory zones:

* [How OpenResty and Nginx Shared Memory Zones Consume RAM](https://blog.openresty.com/en/how-nginx-shm-consume-ram/?src=gh_ngxlua)
* [Memory Fragmentation in OpenResty and Nginx's Shared Memory Zones](https://blog.openresty.com/en/nginx-shm-frag/?src=gh_ngxlua)

[Back to TOC](#directives)

init_by_lua_file
----------------

**syntax:** *init_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http*

**phase:** *loading-config*

Equivalent to [init_by_lua_block](#init_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code or [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.5.5` release.

[Back to TOC](#directives)

init_worker_by_lua
------------------

**syntax:** *init_worker_by_lua &lt;lua-script-str&gt;*

**context:** *http*

**phase:** *starting-worker*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [init_worker_by_lua_block](#init_worker_by_lua_block) directive instead.

Similar to the [init_worker_by_lua_block](#init_worker_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 init_worker_by_lua '
     print("I need no extra escaping here, for example: \r\nblah")
 ';
```

This directive was first introduced in the `v0.9.5` release.

This hook no longer runs in the cache manager and cache loader processes since the `v0.10.12` release.

[Back to TOC](#directives)

init_worker_by_lua_block
------------------------

**syntax:** *init_worker_by_lua_block { lua-script }*

**context:** *http*

**phase:** *starting-worker*

Runs the specified Lua code upon every Nginx worker process's startup when the master process is enabled. When the master process is disabled, this hook will just run after [init_by_lua*](#init_by_lua_block).

This hook is often used to create per-worker reoccurring timers (via the [ngx.timer.at](#ngxtimerat) Lua API), either for backend health-check or other timed routine work. Below is an example,

```nginx

 init_worker_by_lua_block {
     local delay = 3  -- in seconds
     local new_timer = ngx.timer.at
     local log = ngx.log
     local ERR = ngx.ERR
     local check

     check = function(premature)
         if not premature then
             -- do the health check or other routine work
             local ok, err = new_timer(delay, check)
             if not ok then
                 log(ERR, "failed to create timer: ", err)
                 return
             end
         end

         -- do something in timer
     end

     local hdl, err = new_timer(delay, check)
     if not hdl then
         log(ERR, "failed to create timer: ", err)
         return
     end

     -- other job in init_worker_by_lua
 }
```

This directive was first introduced in the `v0.9.17` release.

This hook no longer runs in the cache manager and cache loader processes since the `v0.10.12` release.

[Back to TOC](#directives)

init_worker_by_lua_file
-----------------------

**syntax:** *init_worker_by_lua_file &lt;lua-file-path&gt;*

**context:** *http*

**phase:** *starting-worker*

Similar to [init_worker_by_lua_block](#init_worker_by_lua_block), but accepts the file path to a Lua source file or Lua bytecode file.

This directive was first introduced in the `v0.9.5` release.

This hook no longer runs in the cache manager and cache loader processes since the `v0.10.12` release.

[Back to TOC](#directives)

exit_worker_by_lua_block
------------------------

**syntax:** *exit_worker_by_lua_block { lua-script }*

**context:** *http*

**phase:** *exiting-worker*

Runs the specified Lua code upon every Nginx worker process's exit when the master process is enabled. When the master process is disabled, this hook will run before the Nginx process exits.

This hook is often used to release resources allocated by each worker (e.g. resources allocated by [init_worker_by_lua*](#init_worker_by_lua_block)), or to prevent workers from exiting abnormally.

For example,

```nginx

 exit_worker_by_lua_block {
     print("log from exit_worker_by_lua_block")
 }
```

It's not allowed to create a timer (even a 0-delay timer) here since it runs after all timers have been processed.

This directive was first introduced in the `v0.10.18` release.

[Back to TOC](#directives)

exit_worker_by_lua_file
-----------------------

**syntax:** *exit_worker_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http*

**phase:** *exiting-worker*

Similar to [exit_worker_by_lua_block](#exit_worker_by_lua_block), but accepts the file path to a Lua source file or Lua bytecode file.

This directive was first introduced in the `v0.10.18` release.

[Back to TOC](#directives)

set_by_lua
----------

**syntax:** *set_by_lua $res &lt;lua-script-str&gt; [$arg1 $arg2 ...]*

**context:** *server, server if, location, location if*

**phase:** *rewrite*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [set_by_lua_block](#set_by_lua_block) directive instead.

Similar to the [set_by_lua_block](#set_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping), and
1. this directive support extra arguments after the Lua script.

For example,

```nginx

 set_by_lua $res ' return 32 + math.cos(32) ';
 # $res now has the value "32.834223360507" or alike.
```

As from the `v0.5.0rc29` release, Nginx variable interpolation is disabled in the `<lua-script-str>` argument of this directive and therefore, the dollar sign character (`$`) can be used directly.

This directive requires the [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit) module.

[Back to TOC](#directives)

set_by_lua_block
----------------

**syntax:** *set_by_lua_block $res { lua-script }*

**context:** *server, server if, location, location if*

**phase:** *rewrite*

Executes code specified inside a pair of curly braces (`{}`), and returns string output to `$res`.
The code inside a pair of curly braces (`{}`) can make [API calls](#nginx-api-for-lua) and can retrieve input arguments from the `ngx.arg` table (index starts from `1` and increases sequentially).

This directive is designed to execute short, fast running code blocks as the Nginx event loop is blocked during code execution. Time consuming code sequences should therefore be avoided.

This directive is implemented by injecting custom commands into the standard [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html)'s command list. Because [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html) does not support nonblocking I/O in its commands, Lua APIs requiring yielding the current Lua "light thread" cannot work in this directive.

At least the following API functions are currently disabled within the context of `set_by_lua_block`:

* Output API functions (e.g., [ngx.say](#ngxsay) and [ngx.send_headers](#ngxsend_headers))
* Control API functions (e.g., [ngx.exit](#ngxexit))
* Subrequest API functions (e.g., [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi))
* Cosocket API functions (e.g., [ngx.socket.tcp](#ngxsockettcp) and [ngx.req.socket](#ngxreqsocket)).
* Sleeping API function [ngx.sleep](#ngxsleep).

In addition, note that this directive can only write out a value to a single Nginx variable at
a time. However, a workaround is possible using the [ngx.var.VARIABLE](#ngxvarvariable) interface.

```nginx

 location /foo {
     set $diff ''; # we have to predefine the $diff variable here

     set_by_lua_block $sum {
         local a = 32
         local b = 56

         ngx.var.diff = a - b  -- write to $diff directly
         return a + b          -- return the $sum value normally
     }

     echo "sum = $sum, diff = $diff";
 }
```

This directive can be freely mixed with all directives of the [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html), [set-misc-nginx-module](http://github.com/openresty/set-misc-nginx-module), and [array-var-nginx-module](http://github.com/openresty/array-var-nginx-module) modules. All of these directives will run in the same order as they appear in the config file.

```nginx

 set $foo 32;
 set_by_lua_block $bar { return tonumber(ngx.var.foo) + 1 }
 set $baz "bar: $bar";  # $baz == "bar: 33"
```

No special escaping is required in the Lua code block.

This directive requires the [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit) module.

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

set_by_lua_file
---------------

**syntax:** *set_by_lua_file $res &lt;path-to-lua-script-file&gt; [$arg1 $arg2 ...]*

**context:** *server, server if, location, location if*

**phase:** *rewrite*

Equivalent to [set_by_lua_block](#set_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

Nginx variable interpolation is supported in the `<path-to-lua-script-file>` argument string of this directive. But special care must be taken for injection attacks.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by
switching [lua_code_cache](#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

This directive requires the [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit) module.

[Back to TOC](#directives)

content_by_lua
--------------

**syntax:** *content_by_lua &lt;lua-script-str&gt;*

**context:** *location, location if*

**phase:** *content*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [content_by_lua_block](#content_by_lua_block) directive instead.

Similar to the [content_by_lua_block](#content_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 content_by_lua '
     ngx.say("I need no extra escaping here, for example: \r\nblah")
 ';
```

[Back to TOC](#directives)

content_by_lua_block
--------------------

**syntax:** *content_by_lua_block { lua-script }*

**context:** *location, location if*

**phase:** *content*

For instance,

```nginx

 content_by_lua_block {
     ngx.say("I need no extra escaping here, for example: \r\nblah")
 }
```

Acts as a "content handler" and executes Lua code string specified in `{ lua-script }` for every request.
The Lua code may make [API calls](#nginx-api-for-lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Do not use this directive and other content handler directives in the same location. For example, this directive and the [proxy_pass](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass) directive should not be used in the same location.

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

content_by_lua_file
-------------------

**syntax:** *content_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *location, location if*

**phase:** *content*

Equivalent to [content_by_lua_block](#content_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

If the file is not found, a `404 Not Found` status code will be returned, and a `503 Service Temporarily Unavailable` status code will be returned in case of errors in reading other files.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by
switching [lua_code_cache](#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

Nginx variables are supported in the file path for dynamic dispatch, for example:

```nginx

 # CAUTION: contents in nginx var must be carefully filtered,
 # otherwise there'll be great security risk!
 location ~ ^/app/([-_a-zA-Z0-9/]+) {
     set $path $1;
     content_by_lua_file /path/to/lua/app/root/$path.lua;
 }
```

But be very careful about malicious user inputs and always carefully validate or filter out the user-supplied path components.

[Back to TOC](#directives)

server_rewrite_by_lua_block
---------------------------

**syntax:** *server_rewrite_by_lua_block { lua-script }*

**context:** *http, server*

**phase:** *server rewrite*

Acts as a server rewrite phase handler and executes Lua code string specified in `{ lua-script }` for every request.
The Lua code may make [API calls](#nginx-api-for-lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

```nginx

 server {
     ...

     server_rewrite_by_lua_block {
         ngx.ctx.a = "server_rewrite_by_lua_block in http"
     }

     location /lua {
         content_by_lua_block {
             ngx.say(ngx.ctx.a)
             ngx.log(ngx.INFO, ngx.ctx.a)
        	}
     }
 }
```

Just as any other rewrite phase handlers, [server_rewrite_by_lua_block](#server_rewrite_by_lua_block) also runs in subrequests.

```nginx

 server {
     server_rewrite_by_lua_block {
         ngx.log(ngx.INFO, "is_subrequest:", ngx.is_subrequest)
     }

     location /lua {
         content_by_lua_block {
             local res = ngx.location.capture("/sub")
             ngx.print(res.body)
         }
     }

     location /sub {
         content_by_lua_block {
             ngx.say("OK")
         }
     }
 }
```

Note that when calling `ngx.exit(ngx.OK)` within a [server_rewrite_by_lua_block](#server_rewrite_by_lua_block) handler, the Nginx request processing control flow will still continue to the content handler. To terminate the current request from within a [server_rewrite_by_lua_block](#server_rewrite_by_lua_block) handler, call [ngx.exit](#ngxexit) with status >= 200 (`ngx.HTTP_OK`) and status < 300 (`ngx.HTTP_SPECIAL_RESPONSE`) for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` (or its friends) for failures.


```nginx

 server_rewrite_by_lua_block {
     ngx.exit(503)
 }

 location /bar {
     ...
     # never exec
 }
```


[Back to TOC](#directives)

server_rewrite_by_lua_file
--------------------------

**syntax:** *server_rewrite_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server*

**phase:** *server rewrite*

Equivalent to [server_rewrite_by_lua_block](#server_rewrite_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.10.22` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached and the Nginx config must be reloaded each time the Lua source file is modified. The Lua code cache can be temporarily disabled during development by switching [lua_code_cache](#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

[Back to TOC](#directives)

rewrite_by_lua
--------------

**syntax:** *rewrite_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *rewrite tail*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [rewrite_by_lua_block](#rewrite_by_lua_block) directive instead.

Similar to the [rewrite_by_lua_block](#rewrite_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 rewrite_by_lua '
     do_something("hello, world!\nhiya\n")
 ';
```

[Back to TOC](#directives)

rewrite_by_lua_block
--------------------

**syntax:** *rewrite_by_lua_block { lua-script }*

**context:** *http, server, location, location if*

**phase:** *rewrite tail*

Acts as a rewrite phase handler and executes Lua code string specified in `{ lua-script }` for every request.
The Lua code may make [API calls](#nginx-api-for-lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Note that this handler always runs *after* the standard [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html). So the following will work as expected:

```nginx

 location /foo {
     set $a 12; # create and initialize $a
     set $b ""; # create and initialize $b
     rewrite_by_lua_block {
         ngx.var.b = tonumber(ngx.var.a) + 1
     }
     echo "res = $b";
 }
```

because `set $a 12` and `set $b ""` run *before* [rewrite_by_lua_block](#rewrite_by_lua_block).

On the other hand, the following will not work as expected:

```nginx

 ?  location /foo {
 ?      set $a 12; # create and initialize $a
 ?      set $b ''; # create and initialize $b
 ?      rewrite_by_lua_block {
 ?          ngx.var.b = tonumber(ngx.var.a) + 1
 ?      }
 ?      if ($b = '13') {
 ?         rewrite ^ /bar redirect;
 ?         break;
 ?      }
 ?
 ?      echo "res = $b";
 ?  }
```

because `if` runs *before* [rewrite_by_lua_block](#rewrite_by_lua_block) even if it is placed after [rewrite_by_lua_block](#rewrite_by_lua_block) in the config.

The right way of doing this is as follows:

```nginx

 location /foo {
     set $a 12; # create and initialize $a
     set $b ''; # create and initialize $b
     rewrite_by_lua_block {
         ngx.var.b = tonumber(ngx.var.a) + 1
         if tonumber(ngx.var.b) == 13 then
             return ngx.redirect("/bar")
         end
     }

     echo "res = $b";
 }
```

Note that the [ngx_eval](http://www.grid.net.ru/nginx/eval.en.html) module can be approximated by using [rewrite_by_lua_block](#rewrite_by_lua_block). For example,

```nginx

 location / {
     eval $res {
         proxy_pass http://foo.com/check-spam;
     }

     if ($res = 'spam') {
         rewrite ^ /terms-of-use.html redirect;
     }

     fastcgi_pass ...;
 }
```

can be implemented in ngx_lua as:

```nginx

 location = /check-spam {
     internal;
     proxy_pass http://foo.com/check-spam;
 }

 location / {
     rewrite_by_lua_block {
         local res = ngx.location.capture("/check-spam")
         if res.body == "spam" then
             return ngx.redirect("/terms-of-use.html")
         end
     }

     fastcgi_pass ...;
 }
```

Just as any other rewrite phase handlers, [rewrite_by_lua_block](#rewrite_by_lua_block) also runs in subrequests.

Note that when calling `ngx.exit(ngx.OK)` within a [rewrite_by_lua_block](#rewrite_by_lua_block) handler, the Nginx request processing control flow will still continue to the content handler. To terminate the current request from within a [rewrite_by_lua_block](#rewrite_by_lua_block) handler, call [ngx.exit](#ngxexit) with status >= 200 (`ngx.HTTP_OK`) and status < 300 (`ngx.HTTP_SPECIAL_RESPONSE`) for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` (or its friends) for failures.

If the [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html)'s [rewrite](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite) directive is used to change the URI and initiate location re-lookups (internal redirections), then any [rewrite_by_lua_block](#rewrite_by_lua_block) or [rewrite_by_lua_file_block](#rewrite_by_lua_file_block) code sequences within the current location will not be executed. For example,

```nginx

 location /foo {
     rewrite ^ /bar;
     rewrite_by_lua_block {
         ngx.exit(503)
     }
 }
 location /bar {
     ...
 }
```

Here the Lua code `ngx.exit(503)` will never run. This will be the case if `rewrite ^ /bar last` is used as this will similarly initiate an internal redirection. If the `break` modifier is used instead, there will be no internal redirection and the `rewrite_by_lua_block` code will be executed.

The `rewrite_by_lua_block` code will always run at the end of the `rewrite` request-processing phase unless [rewrite_by_lua_no_postpone](#rewrite_by_lua_no_postpone) is turned on.

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

rewrite_by_lua_file
-------------------

**syntax:** *rewrite_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *rewrite tail*

Equivalent to [rewrite_by_lua_block](#rewrite_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached and the Nginx config must be reloaded each time the Lua source file is modified. The Lua code cache can be temporarily disabled during development by switching [lua_code_cache](#lua_code_cache) `off` in `nginx.conf` to avoid reloading Nginx.

The `rewrite_by_lua_file` code will always run at the end of the `rewrite` request-processing phase unless [rewrite_by_lua_no_postpone](#rewrite_by_lua_no_postpone) is turned on.

Nginx variables are supported in the file path for dynamic dispatch just as in [content_by_lua_file](#content_by_lua_file).

[Back to TOC](#directives)

access_by_lua
-------------

**syntax:** *access_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *access tail*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [access_by_lua_block](#access_by_lua_block) directive instead.

Similar to the [access_by_lua_block](#access_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 access_by_lua '
     do_something("hello, world!\nhiya\n")
 ';
```

[Back to TOC](#directives)

access_by_lua_block
-------------------

**syntax:** *access_by_lua_block { lua-script }*

**context:** *http, server, location, location if*

**phase:** *access tail*

Acts as an access phase handler and executes Lua code string specified in `{ <lua-script }` for every request.
The Lua code may make [API calls](#nginx-api-for-lua) and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).

Note that this handler always runs *after* the standard [ngx_http_access_module](http://nginx.org/en/docs/http/ngx_http_access_module.html). So the following will work as expected:

```nginx

 location / {
     deny    192.168.1.1;
     allow   192.168.1.0/24;
     allow   10.1.1.0/16;
     deny    all;

     access_by_lua_block {
         local res = ngx.location.capture("/mysql", { ... })
         ...
     }

     # proxy_pass/fastcgi_pass/...
 }
```

That is, if a client IP address is in the blacklist, it will be denied before the MySQL query for more complex authentication is executed by [access_by_lua_block](#access_by_lua_block).

Note that the [ngx_auth_request](http://mdounin.ru/hg/ngx_http_auth_request_module/) module can be approximated by using [access_by_lua_block](#access_by_lua_block):

```nginx

 location / {
     auth_request /auth;

     # proxy_pass/fastcgi_pass/postgres_pass/...
 }
```

can be implemented in ngx_lua as:

```nginx

 location / {
     access_by_lua_block {
         local res = ngx.location.capture("/auth")

         if res.status == ngx.HTTP_OK then
             return
         end

         if res.status == ngx.HTTP_FORBIDDEN then
             ngx.exit(res.status)
         end

         ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
     }

     # proxy_pass/fastcgi_pass/postgres_pass/...
 }
```

As with other access phase handlers, [access_by_lua_block](#access_by_lua_block) will *not* run in subrequests.

Note that when calling `ngx.exit(ngx.OK)` within a [access_by_lua_block](#access_by_lua_block) handler, the Nginx request processing control flow will still continue to the content handler. To terminate the current request from within a [access_by_lua_block](#access_by_lua_block) handler, call [ngx.exit](#ngxexit) with status >= 200 (`ngx.HTTP_OK`) and status < 300 (`ngx.HTTP_SPECIAL_RESPONSE`) for successful quits and `ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)` (or its friends) for failures.

Starting from the `v0.9.20` release, you can use the [access_by_lua_no_postpone](#access_by_lua_no_postpone)
directive to control when to run this handler inside the "access" request-processing phase
of Nginx.

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

access_by_lua_file
------------------

**syntax:** *access_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *access tail*

Equivalent to [access_by_lua_block](#access_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

Nginx variables can be used in the `<path-to-lua-script-file>` string to provide flexibility. This however carries some risks and is not ordinarily recommended.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

When the Lua code cache is turned on (by default), the user code is loaded once at the first request and cached
and the Nginx config must be reloaded each time the Lua source file is modified.
The Lua code cache can be temporarily disabled during development by switching [lua_code_cache](#lua_code_cache) `off` in `nginx.conf` to avoid repeatedly reloading Nginx.

Nginx variables are supported in the file path for dynamic dispatch just as in [content_by_lua_file](#content_by_lua_file).

[Back to TOC](#directives)

header_filter_by_lua
--------------------

**syntax:** *header_filter_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *output-header-filter*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [header_filter_by_lua_block](#header_filter_by_lua_block) directive instead.

Similar to the [header_filter_by_lua_block](#header_filter_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 header_filter_by_lua '
     ngx.header["content-length"] = nil
 ';
```

This directive was first introduced in the `v0.2.1rc20` release.

[Back to TOC](#directives)

header_filter_by_lua_block
--------------------------

**syntax:** *header_filter_by_lua_block { lua-script }*

**context:** *http, server, location, location if*

**phase:** *output-header-filter*

Uses Lua code specified in `{ lua-script }` to define an output header filter.

Note that the following API functions are currently disabled within this context:

* Output API functions (e.g., [ngx.say](#ngxsay) and [ngx.send_headers](#ngxsend_headers))
* Control API functions (e.g., [ngx.redirect](#ngxredirect) and [ngx.exec](#ngxexec))
* Subrequest API functions (e.g., [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi))
* Cosocket API functions (e.g., [ngx.socket.tcp](#ngxsockettcp) and [ngx.req.socket](#ngxreqsocket)).

Here is an example of overriding a response header (or adding one if absent) in our Lua header filter:

```nginx

 location / {
     proxy_pass http://mybackend;
     header_filter_by_lua_block {
         ngx.header.Foo = "blah"
     }
 }
```

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

header_filter_by_lua_file
-------------------------

**syntax:** *header_filter_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *output-header-filter*

Equivalent to [header_filter_by_lua_block](#header_filter_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.2.1rc20` release.

[Back to TOC](#directives)

body_filter_by_lua
------------------

**syntax:** *body_filter_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *output-body-filter*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [body_filter_by_lua_block](#body_filter_by_lua_block) directive instead.

Similar to the [body_filter_by_lua_block](#body_filter_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 body_filter_by_lua '
     local data, eof = ngx.arg[1], ngx.arg[2]
 ';
```

This directive was first introduced in the `v0.5.0rc32` release.

[Back to TOC](#directives)

body_filter_by_lua_block
------------------------

**syntax:** *body_filter_by_lua_block { lua-script-str }*

**context:** *http, server, location, location if*

**phase:** *output-body-filter*

Uses Lua code specified in `{ lua-script }` to define an output body filter.

The input data chunk is passed via [ngx.arg](#ngxarg)\[1\] (as a Lua string value) and the "eof" flag indicating the end of the response body data stream is passed via [ngx.arg](#ngxarg)\[2\] (as a Lua boolean value).

Behind the scene, the "eof" flag is just the `last_buf` (for main requests) or `last_in_chain` (for subrequests) flag of the Nginx chain link buffers. (Before the `v0.7.14` release, the "eof" flag does not work at all in subrequests.)

The output data stream can be aborted immediately by running the following Lua statement:

```lua

 return ngx.ERROR
```

This will truncate the response body and usually result in incomplete and also invalid responses.

The Lua code can pass its own modified version of the input data chunk to the downstream Nginx output body filters by overriding [ngx.arg](#ngxarg)\[1\] with a Lua string or a Lua table of strings. For example, to transform all the lowercase letters in the response body, we can just write:

```nginx

 location / {
     proxy_pass http://mybackend;
     body_filter_by_lua_block {
         ngx.arg[1] = string.upper(ngx.arg[1])
     }
 }
```

When setting `nil` or an empty Lua string value to `ngx.arg[1]`, no data chunk will be passed to the downstream Nginx output filters at all.

Likewise, new "eof" flag can also be specified by setting a boolean value to [ngx.arg](#ngxarg)\[2\]. For example,

```nginx

 location /t {
     echo hello world;
     echo hiya globe;

     body_filter_by_lua_block {
         local chunk = ngx.arg[1]
         if string.match(chunk, "hello") then
             ngx.arg[2] = true  -- new eof
             return
         end

         -- just throw away any remaining chunk data
         ngx.arg[1] = nil
     }
 }
```

Then `GET /t` will just return the output


    hello world


That is, when the body filter sees a chunk containing the word "hello", then it will set the "eof" flag to true immediately, resulting in truncated but still valid responses.

When the Lua code may change the length of the response body, then it is required to always clear out the `Content-Length` response header (if any) in a header filter to enforce streaming output, as in

```nginx

 location /foo {
     # fastcgi_pass/proxy_pass/...

     header_filter_by_lua_block {
         ngx.header.content_length = nil
     }
     body_filter_by_lua_block {
         ngx.arg[1] = string.len(ngx.arg[1]) .. "\n"
     }
 }
```

Note that the following API functions are currently disabled within this context due to the limitations in Nginx output filter's current implementation:

* Output API functions (e.g., [ngx.say](#ngxsay) and [ngx.send_headers](#ngxsend_headers))
* Control API functions (e.g., [ngx.exit](#ngxexit) and [ngx.exec](#ngxexec))
* Subrequest API functions (e.g., [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi))
* Cosocket API functions (e.g., [ngx.socket.tcp](#ngxsockettcp) and [ngx.req.socket](#ngxreqsocket)).

Nginx output filters may be called multiple times for a single request because response body may be delivered in chunks. Thus, the Lua code specified by in this directive may also run multiple times in the lifetime of a single HTTP request.

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

body_filter_by_lua_file
-----------------------

**syntax:** *body_filter_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *output-body-filter*

Equivalent to [body_filter_by_lua_block](#body_filter_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.5.0rc32` release.

[Back to TOC](#directives)

log_by_lua
----------

**syntax:** *log_by_lua &lt;lua-script-str&gt;*

**context:** *http, server, location, location if*

**phase:** *log*

**NOTE** Use of this directive is *discouraged* following the `v0.9.17` release. Use the [log_by_lua_block](#log_by_lua_block) directive instead.

Similar to the [log_by_lua_block](#log_by_lua_block) directive, but accepts the Lua source directly in an Nginx string literal (which requires
special character escaping).

For instance,

```nginx

 log_by_lua '
     print("I need no extra escaping here, for example: \r\nblah")
 ';
```

This directive was first introduced in the `v0.5.0rc31` release.

[Back to TOC](#directives)

log_by_lua_block
----------------

**syntax:** *log_by_lua_block { lua-script }*

**context:** *http, server, location, location if*

**phase:** *log*

Runs the Lua source code inlined as the `{ lua-script }` at the `log` request processing phase. This does not replace the current access logs, but runs before.

Note that the following API functions are currently disabled within this context:

* Output API functions (e.g., [ngx.say](#ngxsay) and [ngx.send_headers](#ngxsend_headers))
* Control API functions (e.g., [ngx.exit](#ngxexit))
* Subrequest API functions (e.g., [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi))
* Cosocket API functions (e.g., [ngx.socket.tcp](#ngxsockettcp) and [ngx.req.socket](#ngxreqsocket)).

Here is an example of gathering average data for [$upstream_response_time](http://nginx.org/en/docs/http/ngx_http_upstream_module.html#var_upstream_response_time):

```nginx

 lua_shared_dict log_dict 5M;

 server {
     location / {
         proxy_pass http://mybackend;

         log_by_lua_block {
             local log_dict = ngx.shared.log_dict
             local upstream_time = tonumber(ngx.var.upstream_response_time)

             local sum = log_dict:get("upstream_time-sum") or 0
             sum = sum + upstream_time
             log_dict:set("upstream_time-sum", sum)

             local newval, err = log_dict:incr("upstream_time-nb", 1)
             if not newval and err == "not found" then
                 log_dict:add("upstream_time-nb", 0)
                 log_dict:incr("upstream_time-nb", 1)
             end
         }
     }

     location = /status {
         content_by_lua_block {
             local log_dict = ngx.shared.log_dict
             local sum = log_dict:get("upstream_time-sum")
             local nb = log_dict:get("upstream_time-nb")

             if nb and sum then
                 ngx.say("average upstream response time: ", sum / nb,
                         " (", nb, " reqs)")
             else
                 ngx.say("no data yet")
             end
         }
     }
 }
```

This directive was first introduced in the `v0.9.17` release.

[Back to TOC](#directives)

log_by_lua_file
---------------

**syntax:** *log_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server, location, location if*

**phase:** *log*

Equivalent to [log_by_lua_block](#log_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.5.0rc31` release.

[Back to TOC](#directives)

balancer_by_lua_block
---------------------

**syntax:** *balancer_by_lua_block { lua-script }*

**context:** *upstream*

**phase:** *content*

This directive runs Lua code as an upstream balancer for any upstream entities defined
by the `upstream {}` configuration block.

For instance,

```nginx

 upstream foo {
     server 127.0.0.1;
     balancer_by_lua_block {
         -- use Lua to do something interesting here
         -- as a dynamic balancer
     }
 }

 server {
     location / {
         proxy_pass http://foo;
     }
 }
```

The resulting Lua load balancer can work with any existing Nginx upstream modules
like [ngx_proxy](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) and
[ngx_fastcgi](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html).

Also, the Lua load balancer can work with the standard upstream connection pool mechanism,
i.e., the standard [keepalive](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive) directive.
Just ensure that the [keepalive](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive) directive
is used *after* this `balancer_by_lua_block` directive in a single `upstream {}` configuration block.

The Lua load balancer can totally ignore the list of servers defined in the `upstream {}` block
and select peer from a completely dynamic server list (even changing per request) via the
[ngx.balancer](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md) module
from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library.

The Lua code handler registered by this directive might get called more than once in a single
downstream request when the Nginx upstream mechanism retries the request on conditions
specified by directives like the [proxy_next_upstream](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_next_upstream)
directive.

This Lua code execution context does not support yielding, so Lua APIs that may yield
(like cosockets and "light threads") are disabled in this context. One can usually work
around this limitation by doing such operations in an earlier phase handler (like
[access_by_lua*](#access_by_lua)) and passing along the result into this context
via the [ngx.ctx](#ngxctx) table.

This directive was first introduced in the `v0.10.0` release.

[Back to TOC](#directives)

balancer_by_lua_file
--------------------

**syntax:** *balancer_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *upstream*

**phase:** *content*

Equivalent to [balancer_by_lua_block](#balancer_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.10.0` release.

[Back to TOC](#directives)

lua_need_request_body
---------------------

**syntax:** *lua_need_request_body &lt;on|off&gt;*

**default:** *off*

**context:** *http, server, location, location if*

**phase:** *depends on usage*

Determines whether to force the request body data to be read before running rewrite/access/content_by_lua* or not. The Nginx core does not read the client request body by default and if request body data is required, then this directive should be turned `on` or the [ngx.req.read_body](#ngxreqread_body) function should be called within the Lua code.

To read the request body data within the [$request_body](http://nginx.org/en/docs/http/ngx_http_core_module.html#var_request_body) variable,
[client_body_buffer_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size) must have the same value as [client_max_body_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size). Because when the content length exceeds [client_body_buffer_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size) but less than [client_max_body_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size), Nginx will buffer the data into a temporary file on the disk, which will lead to empty value in the [$request_body](http://nginx.org/en/docs/http/ngx_http_core_module.html#var_request_body) variable.

If the current location includes [rewrite_by_lua*](#rewrite_by_lua) directives,
then the request body will be read just before the [rewrite_by_lua*](#rewrite_by_lua) code is run (and also at the
`rewrite` phase). Similarly, if only [content_by_lua](#content_by_lua) is specified,
the request body will not be read until the content handler's Lua code is
about to run (i.e., the request body will be read during the content phase).

It is recommended however, to use the [ngx.req.read_body](#ngxreqread_body) and [ngx.req.discard_body](#ngxreqdiscard_body) functions for finer control over the request body reading process instead.

This also applies to [access_by_lua*](#access_by_lua).

[Back to TOC](#directives)

ssl_client_hello_by_lua_block
-----------------------------

**syntax:** *ssl_client_hello_by_lua_block { lua-script }*

**context:** *http, server*

**phase:** *right-after-client-hello-message-was-processed*

This directive runs user Lua code when Nginx is about to post-process the SSL client hello message for the downstream
SSL (https) connections.

It is particularly useful for dynamically setting the SSL protocols according to the SNI.

It is also useful to do some custom operations according to the per-connection information in the client hello message.

For example, one can parse custom client hello extension and do the corresponding handling in pure Lua.

This Lua handler will always run whether the SSL session is resumed (via SSL session IDs or TLS session tickets) or not.
While the `ssl_certificate_by_lua*` Lua handler will only runs when initiating a full SSL handshake.

The [ngx.ssl.clienthello](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl/clienthello.md) Lua modules
provided by the [lua-resty-core](https://github.com/openresty/lua-resty-core/#readme)
library are particularly useful in this context.

Note that this handler runs in extremely early stage of SSL handshake, before the SSL client hello extensions are parsed.
So you can not use some Lua API like `ssl.server_name()` which is dependent on the later stage's processing.

Also note that only the directive in default server is valid for several virtual servers with the same IP address and port.

Below is a trivial example using the
[ngx.ssl.clienthello](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl/clienthello.md) module
at the same time:

```nginx

 server {
     listen 443 ssl;
     server_name   test.com;
     ssl_certificate /path/to/cert.crt;
     ssl_certificate_key /path/to/key.key;
     ssl_client_hello_by_lua_block {
         local ssl_clt = require "ngx.ssl.clienthello"
         local host, err = ssl_clt.get_client_hello_server_name()
         if host == "test.com" then
             ssl_clt.set_protocols({"TLSv1", "TLSv1.1"})
         elseif host == "test2.com" then
             ssl_clt.set_protocols({"TLSv1.2", "TLSv1.3"})
         elseif not host then
             ngx.log(ngx.ERR, "failed to get the SNI name: ", err)
             ngx.exit(ngx.ERROR)
         else
             ngx.log(ngx.ERR, "unknown SNI name: ", host)
             ngx.exit(ngx.ERROR)
         end
     }
     ...
 }
 server {
     listen 443 ssl;
     server_name   test2.com;
     ssl_certificate /path/to/cert.crt;
     ssl_certificate_key /path/to/key.key;
     ...
 }
```

See more information in the [ngx.ssl.clienthello](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl/clienthello.md)
Lua modules' official documentation.

Uncaught Lua exceptions in the user Lua code immediately abort the current SSL session, so does the
[ngx.exit](#ngxexit) call with an error code like `ngx.ERROR`.

This Lua code execution context *does* support yielding, so Lua APIs that may yield
(like cosockets, sleeping, and "light threads")
are enabled in this context

Note, you need to configure the [ssl_certificate](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_certificate)
and [ssl_certificate_key](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_certificate_key)
to avoid the following error while starting NGINX:


    nginx: [emerg] no ssl configured for the server


This directive requires OpenSSL 1.1.1 or greater.

If you are using the [official pre-built
packages](https://openresty.org/en/linux-packages.html) for
[OpenResty](https://openresty.org/) 1.21.4.1 or later, then everything should
work out of the box.

If you are not using the Nginx core shipped with
[OpenResty](https://openresty.org) 1.21.4.1 or later, you will need to apply
patches to the standard Nginx core:

<https://openresty.org/en/nginx-ssl-patches.html>

This directive was first introduced in the `v0.10.21` release.

[Back to TOC](#directives)

ssl_client_hello_by_lua_file
----------------------------

**syntax:** *ssl_client_hello_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http, server*

**phase:** *right-after-client-hello-message-was-processed*

Equivalent to [ssl_client_hello_by_lua_block](#ssl_client_hello_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.10.21` release.

[Back to TOC](#directives)

ssl_certificate_by_lua_block
----------------------------

**syntax:** *ssl_certificate_by_lua_block { lua-script }*

**context:** *server*

**phase:** *right-before-SSL-handshake*

This directive runs user Lua code when Nginx is about to start the SSL handshake for the downstream
SSL (https) connections.

It is particularly useful for setting the SSL certificate chain and the corresponding private key on a per-request
basis. It is also useful to load such handshake configurations nonblockingly from the remote (for example,
with the [cosocket](#ngxsockettcp) API). And one can also do per-request OCSP stapling handling in pure
Lua here as well.

Another typical use case is to do SSL handshake traffic control nonblockingly in this context,
with the help of the [lua-resty-limit-traffic#readme](https://github.com/openresty/lua-resty-limit-traffic)
library, for example.

One can also do interesting things with the SSL handshake requests from the client side, like
rejecting old SSL clients using the SSLv3 protocol or even below selectively.

The [ngx.ssl](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md)
and [ngx.ocsp](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ocsp.md) Lua modules
provided by the [lua-resty-core](https://github.com/openresty/lua-resty-core/#readme)
library are particularly useful in this context. You can use the Lua API offered by these two Lua modules
to manipulate the SSL certificate chain and private key for the current SSL connection
being initiated.

This Lua handler does not run at all, however, when Nginx/OpenSSL successfully resumes
the SSL session via SSL session IDs or TLS session tickets for the current SSL connection. In
other words, this Lua handler only runs when Nginx has to initiate a full SSL handshake.

Below is a trivial example using the
[ngx.ssl](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md) module
at the same time:

```nginx

 server {
     listen 443 ssl;
     server_name   test.com;

     ssl_certificate_by_lua_block {
         print("About to initiate a new SSL handshake!")
     }

     location / {
         root html;
     }
 }
```

See more complicated examples in the [ngx.ssl](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md)
and [ngx.ocsp](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ocsp.md)
Lua modules' official documentation.

Uncaught Lua exceptions in the user Lua code immediately abort the current SSL session, so does the
[ngx.exit](#ngxexit) call with an error code like `ngx.ERROR`.

This Lua code execution context *does* support yielding, so Lua APIs that may yield
(like cosockets, sleeping, and "light threads")
are enabled in this context.

Note, however, you still need to configure the [ssl_certificate](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_certificate) and
[ssl_certificate_key](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_certificate_key)
directives even though you will not use this static certificate and private key at all. This is
because the NGINX core requires their appearance otherwise you are seeing the following error
while starting NGINX:


    nginx: [emerg] no ssl configured for the server


This directive requires OpenSSL 1.0.2e or greater.

If you are using the [official pre-built
packages](https://openresty.org/en/linux-packages.html) for
[OpenResty](https://openresty.org/) 1.9.7.2 or later, then everything should
work out of the box.

If you are not using the Nginx core shipped with
[OpenResty](https://openresty.org) 1.9.7.2 or later, you will need to apply
patches to the standard Nginx core:

<https://openresty.org/en/nginx-ssl-patches.html>

This directive was first introduced in the `v0.10.0` release.

[Back to TOC](#directives)

ssl_certificate_by_lua_file
---------------------------

**syntax:** *ssl_certificate_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *server*

**phase:** *right-before-SSL-handshake*

Equivalent to [ssl_certificate_by_lua_block](#ssl_certificate_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or, as from the `v0.5.0rc32` release, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.10.0` release.

[Back to TOC](#directives)

ssl_session_fetch_by_lua_block
------------------------------

**syntax:** *ssl_session_fetch_by_lua_block { lua-script }*

**context:** *http*

**phase:** *right-before-SSL-handshake*

This directive runs Lua code to look up and load the SSL session (if any) according to the session ID
provided by the current SSL handshake request for the downstream.

The Lua API for obtaining the current session ID and loading a cached SSL session data
is provided in the [ngx.ssl.session](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl/session.md)
Lua module shipped with the [lua-resty-core](https://github.com/openresty/lua-resty-core#readme)
library.

Lua APIs that may yield, like [ngx.sleep](#ngxsleep) and [cosockets](#ngxsockettcp),
are enabled in this context.

This hook, together with the [ssl_session_store_by_lua*](#ssl_session_store_by_lua_block) hook,
can be used to implement distributed caching mechanisms in pure Lua (based
on the [cosocket](#ngxsockettcp) API, for example). If a cached SSL session is found
and loaded into the current SSL connection context,
SSL session resumption can then get immediately initiated and bypass the full SSL handshake process which is very expensive in terms of CPU time.

Please note that TLS session tickets are very different and it is the clients' responsibility
to cache the SSL session state when session tickets are used. SSL session resumptions based on
TLS session tickets would happen automatically without going through this hook (nor the
[ssl_session_store_by_lua*](#ssl_session_store_by_lua_block) hook). This hook is mainly
for older or less capable SSL clients that can only do SSL sessions by session IDs.

When [ssl_certificate_by_lua*](#ssl_certificate_by_lua_block) is specified at the same time,
this hook usually runs before [ssl_certificate_by_lua*](#ssl_certificate_by_lua_block).
When the SSL session is found and successfully loaded for the current SSL connection,
SSL session resumption will happen and thus bypass the [ssl_certificate_by_lua*](#ssl_certificate_by_lua_block)
hook completely. In this case, Nginx also bypasses the [ssl_session_store_by_lua*](#ssl_session_store_by_lua_block)
hook, for obvious reasons.

To easily test this hook locally with a modern web browser, you can temporarily put the following line
in your https server block to disable the TLS session ticket support:

    ssl_session_tickets off;

But do not forget to comment this line out before publishing your site to the world.

If you are using the [official pre-built packages](https://openresty.org/en/linux-packages.html) for [OpenResty](https://openresty.org/)
1.11.2.1 or later, then everything should work out of the box.

If you are not using one of the [OpenSSL
packages](https://openresty.org/en/linux-packages.html) provided by
[OpenResty](https://openresty.org), you will need to apply patches to OpenSSL
in order to use this directive:

<https://openresty.org/en/openssl-patches.html>

Similarly, if you are not using the Nginx core shipped with
[OpenResty](https://openresty.org) 1.11.2.1 or later, you will need to apply
patches to the standard Nginx core:

<https://openresty.org/en/nginx-ssl-patches.html>

This directive was first introduced in the `v0.10.6` release.

Note that this directive can only be used in the **http context** starting
with the `v0.10.7` release since SSL session resumption happens
before server name dispatch.

[Back to TOC](#directives)

ssl_session_fetch_by_lua_file
-----------------------------

**syntax:** *ssl_session_fetch_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http*

**phase:** *right-before-SSL-handshake*

Equivalent to [ssl_session_fetch_by_lua_block](#ssl_session_fetch_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or rather, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.10.6` release.

Note that: this directive is only allowed to used in **http context** from the `v0.10.7` release
(because SSL session resumption happens before server name dispatch).

[Back to TOC](#directives)

ssl_session_store_by_lua_block
------------------------------

**syntax:** *ssl_session_store_by_lua_block { lua-script }*

**context:** *http*

**phase:** *right-after-SSL-handshake*

This directive runs Lua code to fetch and save the SSL session (if any) according to the session ID
provided by the current SSL handshake request for the downstream. The saved or cached SSL
session data can be used for future SSL connections to resume SSL sessions without going
through the full SSL handshake process (which is very expensive in terms of CPU time).

Lua APIs that may yield, like [ngx.sleep](#ngxsleep) and [cosockets](#ngxsockettcp),
are *disabled* in this context. You can still, however, use the [ngx.timer.at](#ngxtimerat) API
to create 0-delay timers to save the SSL session data asynchronously to external services (like `redis` or `memcached`).

The Lua API for obtaining the current session ID and the associated session state data
is provided in the [ngx.ssl.session](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl/session.md#readme)
Lua module shipped with the [lua-resty-core](https://github.com/openresty/lua-resty-core#readme)
library.

To easily test this hook locally with a modern web browser, you can temporarily put the following line
in your https server block to disable the TLS session ticket support:

    ssl_session_tickets off;

But do not forget to comment this line out before publishing your site to the world.

This directive was first introduced in the `v0.10.6` release.

Note that: this directive is only allowed to used in **http context** from the `v0.10.7` release
(because SSL session resumption happens before server name dispatch).

[Back to TOC](#directives)

ssl_session_store_by_lua_file
-----------------------------

**syntax:** *ssl_session_store_by_lua_file &lt;path-to-lua-script-file&gt;*

**context:** *http*

**phase:** *right-after-SSL-handshake*

Equivalent to [ssl_session_store_by_lua_block](#ssl_session_store_by_lua_block), except that the file specified by `<path-to-lua-script-file>` contains the Lua code, or rather, the [LuaJIT bytecode](#luajit-bytecode-support) to be executed.

When a relative path like `foo/bar.lua` is given, they will be turned into the absolute path relative to the `server prefix` path determined by the `-p PATH` command-line option while starting the Nginx server.

This directive was first introduced in the `v0.10.6` release.

Note that: this directive is only allowed to used in **http context** from the `v0.10.7` release
(because SSL session resumption happens before server name dispatch).

[Back to TOC](#directives)

lua_shared_dict
---------------

**syntax:** *lua_shared_dict &lt;name&gt; &lt;size&gt;*

**default:** *no*

**context:** *http*

**phase:** *depends on usage*

Declares a shared memory zone, `<name>`, to serve as storage for the shm based Lua dictionary `ngx.shared.<name>`.

Shared memory zones are always shared by all the Nginx worker processes in the current Nginx server instance.

The `<size>` argument accepts size units such as `k` and `m`:

```nginx

 http {
     lua_shared_dict dogs 10m;
     ...
 }
```

The hard-coded minimum size is 8KB while the practical minimum size depends
on actual user data set (some people start with 12KB).

See [ngx.shared.DICT](#ngxshareddict) for details.

This directive was first introduced in the `v0.3.1rc22` release.

[Back to TOC](#directives)

lua_socket_connect_timeout
--------------------------

**syntax:** *lua_socket_connect_timeout &lt;time&gt;*

**default:** *lua_socket_connect_timeout 60s*

**context:** *http, server, location*

This directive controls the default timeout value used in TCP/unix-domain socket object's [connect](#tcpsockconnect) method and can be overridden by the [settimeout](#tcpsocksettimeout) or [settimeouts](#tcpsocksettimeouts) methods.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_send_timeout
-----------------------

**syntax:** *lua_socket_send_timeout &lt;time&gt;*

**default:** *lua_socket_send_timeout 60s*

**context:** *http, server, location*

Controls the default timeout value used in TCP/unix-domain socket object's [send](#tcpsocksend) method and can be overridden by the [settimeout](#tcpsocksettimeout) or [settimeouts](#tcpsocksettimeouts) methods.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_send_lowat
---------------------

**syntax:** *lua_socket_send_lowat &lt;size&gt;*

**default:** *lua_socket_send_lowat 0*

**context:** *http, server, location*

Controls the `lowat` (low water) value for the cosocket send buffer.

[Back to TOC](#directives)

lua_socket_read_timeout
-----------------------

**syntax:** *lua_socket_read_timeout &lt;time&gt;*

**default:** *lua_socket_read_timeout 60s*

**context:** *http, server, location*

**phase:** *depends on usage*

This directive controls the default timeout value used in TCP/unix-domain socket object's [receive](#tcpsockreceive) method and iterator functions returned by the [receiveuntil](#tcpsockreceiveuntil) method. This setting can be overridden by the [settimeout](#tcpsocksettimeout) or [settimeouts](#tcpsocksettimeouts) methods.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_buffer_size
----------------------

**syntax:** *lua_socket_buffer_size &lt;size&gt;*

**default:** *lua_socket_buffer_size 4k/8k*

**context:** *http, server, location*

Specifies the buffer size used by cosocket reading operations.

This buffer does not have to be that big to hold everything at the same time because cosocket supports 100% non-buffered reading and parsing. So even `1` byte buffer size should still work everywhere but the performance could be terrible.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_pool_size
--------------------

**syntax:** *lua_socket_pool_size &lt;size&gt;*

**default:** *lua_socket_pool_size 30*

**context:** *http, server, location*

Specifies the size limit (in terms of connection count) for every cosocket connection pool associated with every remote server (i.e., identified by either the host-port pair or the unix domain socket file path).

Default to 30 connections for every pool.

When the connection pool exceeds the available size limit, the least recently used (idle) connection already in the pool will be closed to make room for the current connection.

Note that the cosocket connection pool is per Nginx worker process rather than per Nginx server instance, so size limit specified here also applies to every single Nginx worker process.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_keepalive_timeout
----------------------------

**syntax:** *lua_socket_keepalive_timeout &lt;time&gt;*

**default:** *lua_socket_keepalive_timeout 60s*

**context:** *http, server, location*

This directive controls the default maximal idle time of the connections in the cosocket built-in connection pool. When this timeout reaches, idle connections will be closed and removed from the pool. This setting can be overridden by cosocket objects' [setkeepalive](#tcpsocksetkeepalive) method.

The `<time>` argument can be an integer, with an optional time unit, like `s` (second), `ms` (millisecond), `m` (minute). The default time unit is `s`, i.e., "second". The default setting is `60s`.

This directive was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#directives)

lua_socket_log_errors
---------------------

**syntax:** *lua_socket_log_errors on|off*

**default:** *lua_socket_log_errors on*

**context:** *http, server, location*

This directive can be used to toggle error logging when a failure occurs for the TCP or UDP cosockets. If you are already doing proper error handling and logging in your Lua code, then it is recommended to turn this directive off to prevent data flushing in your Nginx error log files (which is usually rather expensive).

This directive was first introduced in the `v0.5.13` release.

[Back to TOC](#directives)

lua_ssl_ciphers
---------------

**syntax:** *lua_ssl_ciphers &lt;ciphers&gt;*

**default:** *lua_ssl_ciphers DEFAULT*

**context:** *http, server, location*

Specifies the enabled ciphers for requests to a SSL/TLS server in the [tcpsock:sslhandshake](#tcpsocksslhandshake) method. The ciphers are specified in the format understood by the OpenSSL library.

The full list can be viewed using the “openssl ciphers” command.

This directive was first introduced in the `v0.9.11` release.

[Back to TOC](#directives)

lua_ssl_crl
-----------

**syntax:** *lua_ssl_crl &lt;file&gt;*

**default:** *no*

**context:** *http, server, location*

Specifies a file with revoked certificates (CRL) in the PEM format used to verify the certificate of the SSL/TLS server in the [tcpsock:sslhandshake](#tcpsocksslhandshake) method.

This directive was first introduced in the `v0.9.11` release.

[Back to TOC](#directives)

lua_ssl_protocols
-----------------

**syntax:** *lua_ssl_protocols \[SSLv2\] \[SSLv3\] \[TLSv1\] [TLSv1.1] [TLSv1.2] [TLSv1.3]*

**default:** *lua_ssl_protocols SSLv3 TLSv1 TLSv1.1 TLSv1.2*

**context:** *http, server, location*

Enables the specified protocols for requests to a SSL/TLS server in the [tcpsock:sslhandshake](#tcpsocksslhandshake) method.

The support for the `TLSv1.3` parameter requires version `v0.10.12` *and* OpenSSL 1.1.1.

This directive was first introduced in the `v0.9.11` release.

[Back to TOC](#directives)

lua_ssl_trusted_certificate
---------------------------

**syntax:** *lua_ssl_trusted_certificate &lt;file&gt;*

**default:** *no*

**context:** *http, server, location*

Specifies a file path with trusted CA certificates in the PEM format used to verify the certificate of the SSL/TLS server in the [tcpsock:sslhandshake](#tcpsocksslhandshake) method.

This directive was first introduced in the `v0.9.11` release.

See also [lua_ssl_verify_depth](#lua_ssl_verify_depth).

[Back to TOC](#directives)

lua_ssl_verify_depth
--------------------

**syntax:** *lua_ssl_verify_depth &lt;number&gt;*

**default:** *lua_ssl_verify_depth 1*

**context:** *http, server, location*

Sets the verification depth in the server certificates chain.

This directive was first introduced in the `v0.9.11` release.

See also [lua_ssl_trusted_certificate](#lua_ssl_trusted_certificate).

[Back to TOC](#directives)

lua_ssl_conf_command
--------------------

**syntax:** *lua_ssl_conf_command &lt;command&gt;*

**default:** *no*

**context:** *http, server, location*

Sets arbitrary OpenSSL configuration [commands](https://www.openssl.org/docs/man1.1.1/man3/SSL_CONF_cmd.html).

The directive is supported when using OpenSSL 1.0.2 or higher and nginx 1.19.4 or higher. According to the specify command, higher OpenSSL version may be needed.

Several `lua_ssl_conf_command` directives can be specified on the same level:

```nginx

 lua_ssl_conf_command Options PrioritizeChaCha;
 lua_ssl_conf_command Ciphersuites TLS_CHACHA20_POLY1305_SHA256;
```

Configuration commands are applied after OpenResty own configuration for SSL, so they can be used to override anything set by OpenResty.

Note though that configuring OpenSSL directly with `lua_ssl_conf_command` might result in a behaviour OpenResty does not expect, and should be done with care.

This directive was first introduced in the `v0.10.21` release.



[Back to TOC](#directives)

lua_http10_buffering
--------------------

**syntax:** *lua_http10_buffering on|off*

**default:** *lua_http10_buffering on*

**context:** *http, server, location, location-if*

Enables or disables automatic response buffering for HTTP 1.0 (or older) requests. This buffering mechanism is mainly used for HTTP 1.0 keep-alive which relies on a proper `Content-Length` response header.

If the Lua code explicitly sets a `Content-Length` response header before sending the headers (either explicitly via [ngx.send_headers](#ngxsend_headers) or implicitly via the first [ngx.say](#ngxsay) or [ngx.print](#ngxprint) call), then the HTTP 1.0 response buffering will be disabled even when this directive is turned on.

To output very large response data in a streaming fashion (via the [ngx.flush](#ngxflush) call, for example), this directive MUST be turned off to minimize memory usage.

This directive is turned `on` by default.

This directive was first introduced in the `v0.5.0rc19` release.

[Back to TOC](#directives)

rewrite_by_lua_no_postpone
--------------------------

**syntax:** *rewrite_by_lua_no_postpone on|off*

**default:** *rewrite_by_lua_no_postpone off*

**context:** *http*

Controls whether or not to disable postponing [rewrite_by_lua*](#rewrite_by_lua) directives to run at the end of the `rewrite` request-processing phase. By default, this directive is turned off and the Lua code is postponed to run at the end of the `rewrite` phase.

This directive was first introduced in the `v0.5.0rc29` release.

[Back to TOC](#directives)

access_by_lua_no_postpone
-------------------------

**syntax:** *access_by_lua_no_postpone on|off*

**default:** *access_by_lua_no_postpone off*

**context:** *http*

Controls whether or not to disable postponing [access_by_lua*](#access_by_lua) directives to run at the end of the `access` request-processing phase. By default, this directive is turned off and the Lua code is postponed to run at the end of the `access` phase.

This directive was first introduced in the `v0.9.20` release.

[Back to TOC](#directives)

lua_transform_underscores_in_response_headers
---------------------------------------------

**syntax:** *lua_transform_underscores_in_response_headers on|off*

**default:** *lua_transform_underscores_in_response_headers on*

**context:** *http, server, location, location-if*

Controls whether to transform underscores (`_`) in the response header names specified in the [ngx.header.HEADER](#ngxheaderheader) API to hyphens (`-`).

This directive was first introduced in the `v0.5.0rc32` release.

[Back to TOC](#directives)

lua_check_client_abort
----------------------

**syntax:** *lua_check_client_abort on|off*

**default:** *lua_check_client_abort off*

**context:** *http, server, location, location-if*

This directive controls whether to check for premature client connection abortion.

When this directive is on, the ngx_lua module will monitor the premature connection close event on the downstream connections and when there is such an event, it will call the user Lua function callback (registered by [ngx.on_abort](#ngxon_abort)) or just stop and clean up all the Lua "light threads" running in the current request's request handler when there is no user callback function registered.

According to the current implementation, however, if the client closes the connection before the Lua code finishes reading the request body data via [ngx.req.socket](#ngxreqsocket), then ngx_lua will neither stop all the running "light threads" nor call the user callback (if [ngx.on_abort](#ngxon_abort) has been called). Instead, the reading operation on [ngx.req.socket](#ngxreqsocket) will just return the error message "client aborted" as the second return value (the first return value is surely `nil`).

When TCP keepalive is disabled, it is relying on the client side to close the socket gracefully (by sending a `FIN` packet or something like that). For (soft) real-time web applications, it is highly recommended to configure the [TCP keepalive](http://tldp.org/HOWTO/TCP-Keepalive-HOWTO/overview.html) support in your system's TCP stack implementation in order to detect "half-open" TCP connections in time.

For example, on Linux, you can configure the standard [listen](http://nginx.org/en/docs/http/ngx_http_core_module.html#listen) directive in your `nginx.conf` file like this:

```nginx

 listen 80 so_keepalive=2s:2s:8;
```

On FreeBSD, you can only tune the system-wide configuration for TCP keepalive, for example:

    # sysctl net.inet.tcp.keepintvl=2000
    # sysctl net.inet.tcp.keepidle=2000

This directive was first introduced in the `v0.7.4` release.

See also [ngx.on_abort](#ngxon_abort).

[Back to TOC](#directives)

lua_max_pending_timers
----------------------

**syntax:** *lua_max_pending_timers &lt;count&gt;*

**default:** *lua_max_pending_timers 1024*

**context:** *http*

Controls the maximum number of pending timers allowed.

Pending timers are those timers that have not expired yet.

When exceeding this limit, the [ngx.timer.at](#ngxtimerat) call will immediately return `nil` and the error string "too many pending timers".

This directive was first introduced in the `v0.8.0` release.

[Back to TOC](#directives)

lua_max_running_timers
----------------------

**syntax:** *lua_max_running_timers &lt;count&gt;*

**default:** *lua_max_running_timers 256*

**context:** *http*

Controls the maximum number of "running timers" allowed.

Running timers are those timers whose user callback functions are still running or `lightthreads` spawned in callback functions are still running.

When exceeding this limit, Nginx will stop running the callbacks of newly expired timers and log an error message "N lua_max_running_timers are not enough" where "N" is the current value of this directive.

This directive was first introduced in the `v0.8.0` release.

[Back to TOC](#directives)

lua_sa_restart
--------------

**syntax:** *lua_sa_restart on|off*

**default:** *lua_sa_restart on*

**context:** *http*

When enabled, this module will set the `SA_RESTART` flag on Nginx workers signal dispositions.

This allows Lua I/O primitives to not be interrupted by Nginx's handling of various signals.

This directive was first introduced in the `v0.10.14` release.

[Back to TOC](#directives)

lua_worker_thread_vm_pool_size
------------------------------

**syntax:** *lua_worker_thread_vm_pool_size &lt;size&gt;*

**default:** *lua_worker_thread_vm_pool_size 100*

**context:** *http*

Specifies the size limit of the Lua VM pool (default 100) that will be used in the [ngx.run_worker_thread](#ngxrun_worker_thread) API.

Also, it is not allowed to create Lua VMs that exceeds the pool size limit.

The Lua VM in the VM pool is used to execute Lua code in separate thread.

The pool is global at Nginx worker level. And it is used to reuse Lua VMs between requests.

[Back to TOC](#directives)

Nginx API for Lua
=================

* [Introduction](#introduction)
* [ngx.arg](#ngxarg)
* [ngx.var.VARIABLE](#ngxvarvariable)
* [Core constants](#core-constants)
* [HTTP method constants](#http-method-constants)
* [HTTP status constants](#http-status-constants)
* [Nginx log level constants](#nginx-log-level-constants)
* [print](#print)
* [ngx.ctx](#ngxctx)
* [ngx.location.capture](#ngxlocationcapture)
* [ngx.location.capture_multi](#ngxlocationcapture_multi)
* [ngx.status](#ngxstatus)
* [ngx.header.HEADER](#ngxheaderheader)
* [ngx.resp.get_headers](#ngxrespget_headers)
* [ngx.req.is_internal](#ngxreqis_internal)
* [ngx.req.start_time](#ngxreqstart_time)
* [ngx.req.http_version](#ngxreqhttp_version)
* [ngx.req.raw_header](#ngxreqraw_header)
* [ngx.req.get_method](#ngxreqget_method)
* [ngx.req.set_method](#ngxreqset_method)
* [ngx.req.set_uri](#ngxreqset_uri)
* [ngx.req.set_uri_args](#ngxreqset_uri_args)
* [ngx.req.get_uri_args](#ngxreqget_uri_args)
* [ngx.req.get_post_args](#ngxreqget_post_args)
* [ngx.req.get_headers](#ngxreqget_headers)
* [ngx.req.set_header](#ngxreqset_header)
* [ngx.req.clear_header](#ngxreqclear_header)
* [ngx.req.read_body](#ngxreqread_body)
* [ngx.req.discard_body](#ngxreqdiscard_body)
* [ngx.req.get_body_data](#ngxreqget_body_data)
* [ngx.req.get_body_file](#ngxreqget_body_file)
* [ngx.req.set_body_data](#ngxreqset_body_data)
* [ngx.req.set_body_file](#ngxreqset_body_file)
* [ngx.req.init_body](#ngxreqinit_body)
* [ngx.req.append_body](#ngxreqappend_body)
* [ngx.req.finish_body](#ngxreqfinish_body)
* [ngx.req.socket](#ngxreqsocket)
* [ngx.exec](#ngxexec)
* [ngx.redirect](#ngxredirect)
* [ngx.send_headers](#ngxsend_headers)
* [ngx.headers_sent](#ngxheaders_sent)
* [ngx.print](#ngxprint)
* [ngx.say](#ngxsay)
* [ngx.log](#ngxlog)
* [ngx.flush](#ngxflush)
* [ngx.exit](#ngxexit)
* [ngx.eof](#ngxeof)
* [ngx.sleep](#ngxsleep)
* [ngx.escape_uri](#ngxescape_uri)
* [ngx.unescape_uri](#ngxunescape_uri)
* [ngx.encode_args](#ngxencode_args)
* [ngx.decode_args](#ngxdecode_args)
* [ngx.encode_base64](#ngxencode_base64)
* [ngx.decode_base64](#ngxdecode_base64)
* [ngx.crc32_short](#ngxcrc32_short)
* [ngx.crc32_long](#ngxcrc32_long)
* [ngx.hmac_sha1](#ngxhmac_sha1)
* [ngx.md5](#ngxmd5)
* [ngx.md5_bin](#ngxmd5_bin)
* [ngx.sha1_bin](#ngxsha1_bin)
* [ngx.quote_sql_str](#ngxquote_sql_str)
* [ngx.today](#ngxtoday)
* [ngx.time](#ngxtime)
* [ngx.now](#ngxnow)
* [ngx.update_time](#ngxupdate_time)
* [ngx.localtime](#ngxlocaltime)
* [ngx.utctime](#ngxutctime)
* [ngx.cookie_time](#ngxcookie_time)
* [ngx.http_time](#ngxhttp_time)
* [ngx.parse_http_time](#ngxparse_http_time)
* [ngx.is_subrequest](#ngxis_subrequest)
* [ngx.re.match](#ngxrematch)
* [ngx.re.find](#ngxrefind)
* [ngx.re.gmatch](#ngxregmatch)
* [ngx.re.sub](#ngxresub)
* [ngx.re.gsub](#ngxregsub)
* [ngx.shared.DICT](#ngxshareddict)
* [ngx.shared.DICT.get](#ngxshareddictget)
* [ngx.shared.DICT.get_stale](#ngxshareddictget_stale)
* [ngx.shared.DICT.set](#ngxshareddictset)
* [ngx.shared.DICT.safe_set](#ngxshareddictsafe_set)
* [ngx.shared.DICT.add](#ngxshareddictadd)
* [ngx.shared.DICT.safe_add](#ngxshareddictsafe_add)
* [ngx.shared.DICT.replace](#ngxshareddictreplace)
* [ngx.shared.DICT.delete](#ngxshareddictdelete)
* [ngx.shared.DICT.incr](#ngxshareddictincr)
* [ngx.shared.DICT.lpush](#ngxshareddictlpush)
* [ngx.shared.DICT.rpush](#ngxshareddictrpush)
* [ngx.shared.DICT.lpop](#ngxshareddictlpop)
* [ngx.shared.DICT.rpop](#ngxshareddictrpop)
* [ngx.shared.DICT.llen](#ngxshareddictllen)
* [ngx.shared.DICT.ttl](#ngxshareddictttl)
* [ngx.shared.DICT.expire](#ngxshareddictexpire)
* [ngx.shared.DICT.flush_all](#ngxshareddictflush_all)
* [ngx.shared.DICT.flush_expired](#ngxshareddictflush_expired)
* [ngx.shared.DICT.get_keys](#ngxshareddictget_keys)
* [ngx.shared.DICT.capacity](#ngxshareddictcapacity)
* [ngx.shared.DICT.free_space](#ngxshareddictfree_space)
* [ngx.socket.udp](#ngxsocketudp)
* [udpsock:setpeername](#udpsocksetpeername)
* [udpsock:send](#udpsocksend)
* [udpsock:receive](#udpsockreceive)
* [udpsock:close](#udpsockclose)
* [udpsock:settimeout](#udpsocksettimeout)
* [ngx.socket.stream](#ngxsocketstream)
* [ngx.socket.tcp](#ngxsockettcp)
* [tcpsock:bind](#tcpsockbind)
* [tcpsock:connect](#tcpsockconnect)
* [tcpsock:setclientcert](#tcpsocksetclientcert)
* [tcpsock:sslhandshake](#tcpsocksslhandshake)
* [tcpsock:send](#tcpsocksend)
* [tcpsock:receive](#tcpsockreceive)
* [tcpsock:receiveany](#tcpsockreceiveany)
* [tcpsock:receiveuntil](#tcpsockreceiveuntil)
* [tcpsock:close](#tcpsockclose)
* [tcpsock:settimeout](#tcpsocksettimeout)
* [tcpsock:settimeouts](#tcpsocksettimeouts)
* [tcpsock:setoption](#tcpsocksetoption)
* [tcpsock:setkeepalive](#tcpsocksetkeepalive)
* [tcpsock:getreusedtimes](#tcpsockgetreusedtimes)
* [ngx.socket.connect](#ngxsocketconnect)
* [ngx.get_phase](#ngxget_phase)
* [ngx.thread.spawn](#ngxthreadspawn)
* [ngx.thread.wait](#ngxthreadwait)
* [ngx.thread.kill](#ngxthreadkill)
* [ngx.on_abort](#ngxon_abort)
* [ngx.timer.at](#ngxtimerat)
* [ngx.timer.every](#ngxtimerevery)
* [ngx.timer.running_count](#ngxtimerrunning_count)
* [ngx.timer.pending_count](#ngxtimerpending_count)
* [ngx.config.subsystem](#ngxconfigsubsystem)
* [ngx.config.debug](#ngxconfigdebug)
* [ngx.config.prefix](#ngxconfigprefix)
* [ngx.config.nginx_version](#ngxconfignginx_version)
* [ngx.config.nginx_configure](#ngxconfignginx_configure)
* [ngx.config.ngx_lua_version](#ngxconfigngx_lua_version)
* [ngx.worker.exiting](#ngxworkerexiting)
* [ngx.worker.pid](#ngxworkerpid)
* [ngx.worker.pids](#ngxworkerpids)
* [ngx.worker.count](#ngxworkercount)
* [ngx.worker.id](#ngxworkerid)
* [ngx.semaphore](#ngxsemaphore)
* [ngx.balancer](#ngxbalancer)
* [ngx.ssl](#ngxssl)
* [ngx.ocsp](#ngxocsp)
* [ndk.set_var.DIRECTIVE](#ndkset_vardirective)
* [coroutine.create](#coroutinecreate)
* [coroutine.resume](#coroutineresume)
* [coroutine.yield](#coroutineyield)
* [coroutine.wrap](#coroutinewrap)
* [coroutine.running](#coroutinerunning)
* [coroutine.status](#coroutinestatus)
* [ngx.run_worker_thread](#ngxrun_worker_thread)


[Back to TOC](#table-of-contents)

Introduction
------------

The various `*_by_lua`, `*_by_lua_block` and `*_by_lua_file` configuration directives serve as gateways to the Lua API within the `nginx.conf` file. The Nginx Lua API described below can only be called within the user Lua code run in the context of these configuration directives.

The API is exposed to Lua in the form of two standard packages `ngx` and `ndk`. These packages are in the default global scope within ngx_lua and are always available within ngx_lua directives.

The packages can be introduced into external Lua modules like this:

```lua

 local say = ngx.say

 local _M = {}

 function _M.foo(a)
     say(a)
 end

 return _M
```

Use of the [package.seeall](https://www.lua.org/manual/5.1/manual.html#pdf-package.seeall) flag is strongly discouraged due to its various bad side-effects.

It is also possible to directly require the packages in external Lua modules:

```lua

 local ngx = require "ngx"
 local ndk = require "ndk"
```

The ability to require these packages was introduced in the `v0.2.1rc19` release.

Network I/O operations in user code should only be done through the Nginx Lua API calls as the Nginx event loop may be blocked and performance drop off dramatically otherwise. Disk operations with relatively small amount of data can be done using the standard Lua `io` library but huge file reading and writing should be avoided wherever possible as they may block the Nginx process significantly. Delegating all network and disk I/O operations to Nginx's subrequests (via the [ngx.location.capture](#ngxlocationcapture) method and similar) is strongly recommended for maximum performance.

[Back to TOC](#nginx-api-for-lua)

ngx.arg
-------

**syntax:** *val = ngx.arg\[index\]*

**context:** *set_by_lua&#42;, body_filter_by_lua&#42;*

When this is used in the context of the [set_by_lua*](#set_by_lua) directives, this table is read-only and holds the input arguments to the config directives:

```lua

 value = ngx.arg[n]
```

Here is an example

```nginx

 location /foo {
     set $a 32;
     set $b 56;

     set_by_lua $sum
         'return tonumber(ngx.arg[1]) + tonumber(ngx.arg[2])'
         $a $b;

     echo $sum;
 }
```

that writes out `88`, the sum of `32` and `56`.

When this table is used in the context of [body_filter_by_lua*](#body_filter_by_lua), the first element holds the input data chunk to the output filter code and the second element holds the boolean flag for the "eof" flag indicating the end of the whole output data stream.

The data chunk and "eof" flag passed to the downstream Nginx output filters can also be overridden by assigning values directly to the corresponding table elements. When setting `nil` or an empty Lua string value to `ngx.arg[1]`, no data chunk will be passed to the downstream Nginx output filters at all.

[Back to TOC](#nginx-api-for-lua)

ngx.var.VARIABLE
----------------

**syntax:** *ngx.var.VAR_NAME*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, balancer_by_lua&#42;*

Read and write Nginx variable values.

```nginx

 value = ngx.var.some_nginx_variable_name
 ngx.var.some_nginx_variable_name = value
```

Note that only already defined Nginx variables can be written to.
For example:

```nginx

 location /foo {
     set $my_var ''; # this line is required to create $my_var at config time
     content_by_lua_block {
         ngx.var.my_var = 123
         ...
     }
 }
```

That is, Nginx variables cannot be created on-the-fly. Here is a list of pre-defined
[Nginx variables](http://nginx.org/en/docs/varindex.html).

Some special Nginx variables like `$args` and `$limit_rate` can be assigned a value,
many others are not, like `$query_string`, `$arg_PARAMETER`, and `$http_NAME`.

Nginx regex group capturing variables `$1`, `$2`, `$3`, and etc, can be read by this
interface as well, by writing `ngx.var[1]`, `ngx.var[2]`, `ngx.var[3]`, and etc.

Setting `ngx.var.Foo` to a `nil` value will unset the `$Foo` Nginx variable.

```lua

 ngx.var.args = nil
```

**CAUTION** When reading from an Nginx variable, Nginx will allocate memory in the per-request memory pool which is freed only at request termination. So when you need to read from an Nginx variable repeatedly in your Lua code, cache the Nginx variable value to your own Lua variable, for example,

```lua

 local val = ngx.var.some_var
 --- use the val repeatedly later
```

to prevent (temporary) memory leaking within the current request's lifetime. Another way of caching the result is to use the [ngx.ctx](#ngxctx) table.

Undefined Nginx variables are evaluated to `nil` while uninitialized (but defined) Nginx variables are evaluated to an empty Lua string.

This API requires a relatively expensive metamethod call and it is recommended to avoid using it on hot code paths.

[Back to TOC](#nginx-api-for-lua)

Core constants
--------------

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, &#42;log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

```lua

   ngx.OK (0)
   ngx.ERROR (-1)
   ngx.AGAIN (-2)
   ngx.DONE (-4)
   ngx.DECLINED (-5)
```

Note that only three of these constants are utilized by the [Nginx API for Lua](#nginx-api-for-lua) (i.e., [ngx.exit](#ngxexit) accepts `ngx.OK`, `ngx.ERROR`, and `ngx.DECLINED` as input).

```lua

   ngx.null
```

The `ngx.null` constant is a `NULL` light userdata usually used to represent nil values in Lua tables etc and is similar to the [lua-cjson](http://www.kyne.com.au/~mark/software/lua-cjson.php) library's `cjson.null` constant. This constant was first introduced in the `v0.5.0rc5` release.

The `ngx.DECLINED` constant was first introduced in the `v0.5.0rc19` release.

[Back to TOC](#nginx-api-for-lua)

HTTP method constants
---------------------

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*


      ngx.HTTP_GET
      ngx.HTTP_HEAD
      ngx.HTTP_PUT
      ngx.HTTP_POST
      ngx.HTTP_DELETE
      ngx.HTTP_OPTIONS   (added in the v0.5.0rc24 release)
      ngx.HTTP_MKCOL     (added in the v0.8.2 release)
      ngx.HTTP_COPY      (added in the v0.8.2 release)
      ngx.HTTP_MOVE      (added in the v0.8.2 release)
      ngx.HTTP_PROPFIND  (added in the v0.8.2 release)
      ngx.HTTP_PROPPATCH (added in the v0.8.2 release)
      ngx.HTTP_LOCK      (added in the v0.8.2 release)
      ngx.HTTP_UNLOCK    (added in the v0.8.2 release)
      ngx.HTTP_PATCH     (added in the v0.8.2 release)
      ngx.HTTP_TRACE     (added in the v0.8.2 release)


These constants are usually used in [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi) method calls.

[Back to TOC](#nginx-api-for-lua)

HTTP status constants
---------------------

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

```nginx

   value = ngx.HTTP_CONTINUE (100) (first added in the v0.9.20 release)
   value = ngx.HTTP_SWITCHING_PROTOCOLS (101) (first added in the v0.9.20 release)
   value = ngx.HTTP_OK (200)
   value = ngx.HTTP_CREATED (201)
   value = ngx.HTTP_ACCEPTED (202) (first added in the v0.9.20 release)
   value = ngx.HTTP_NO_CONTENT (204) (first added in the v0.9.20 release)
   value = ngx.HTTP_PARTIAL_CONTENT (206) (first added in the v0.9.20 release)
   value = ngx.HTTP_SPECIAL_RESPONSE (300)
   value = ngx.HTTP_MOVED_PERMANENTLY (301)
   value = ngx.HTTP_MOVED_TEMPORARILY (302)
   value = ngx.HTTP_SEE_OTHER (303)
   value = ngx.HTTP_NOT_MODIFIED (304)
   value = ngx.HTTP_TEMPORARY_REDIRECT (307) (first added in the v0.9.20 release)
   value = ngx.HTTP_PERMANENT_REDIRECT (308)
   value = ngx.HTTP_BAD_REQUEST (400)
   value = ngx.HTTP_UNAUTHORIZED (401)
   value = ngx.HTTP_PAYMENT_REQUIRED (402) (first added in the v0.9.20 release)
   value = ngx.HTTP_FORBIDDEN (403)
   value = ngx.HTTP_NOT_FOUND (404)
   value = ngx.HTTP_NOT_ALLOWED (405)
   value = ngx.HTTP_NOT_ACCEPTABLE (406) (first added in the v0.9.20 release)
   value = ngx.HTTP_REQUEST_TIMEOUT (408) (first added in the v0.9.20 release)
   value = ngx.HTTP_CONFLICT (409) (first added in the v0.9.20 release)
   value = ngx.HTTP_GONE (410)
   value = ngx.HTTP_UPGRADE_REQUIRED (426) (first added in the v0.9.20 release)
   value = ngx.HTTP_TOO_MANY_REQUESTS (429) (first added in the v0.9.20 release)
   value = ngx.HTTP_CLOSE (444) (first added in the v0.9.20 release)
   value = ngx.HTTP_ILLEGAL (451) (first added in the v0.9.20 release)
   value = ngx.HTTP_INTERNAL_SERVER_ERROR (500)
   value = ngx.HTTP_NOT_IMPLEMENTED (501)
   value = ngx.HTTP_METHOD_NOT_IMPLEMENTED (501) (kept for compatibility)
   value = ngx.HTTP_BAD_GATEWAY (502) (first added in the v0.9.20 release)
   value = ngx.HTTP_SERVICE_UNAVAILABLE (503)
   value = ngx.HTTP_GATEWAY_TIMEOUT (504) (first added in the v0.3.1rc38 release)
   value = ngx.HTTP_VERSION_NOT_SUPPORTED (505) (first added in the v0.9.20 release)
   value = ngx.HTTP_INSUFFICIENT_STORAGE (507) (first added in the v0.9.20 release)
```

[Back to TOC](#nginx-api-for-lua)

Nginx log level constants
-------------------------

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

```lua

   ngx.STDERR
   ngx.EMERG
   ngx.ALERT
   ngx.CRIT
   ngx.ERR
   ngx.WARN
   ngx.NOTICE
   ngx.INFO
   ngx.DEBUG
```

These constants are usually used by the [ngx.log](#ngxlog) method.

[Back to TOC](#nginx-api-for-lua)

print
-----

**syntax:** *print(...)*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Writes argument values into the Nginx `error.log` file with the `ngx.NOTICE` log level.

It is equivalent to

```lua

 ngx.log(ngx.NOTICE, ...)
```

Lua `nil` arguments are accepted and result in literal `"nil"` strings while Lua booleans result in literal `"true"` or `"false"` strings. And the `ngx.null` constant will yield the `"null"` string output.

There is a hard coded `2048` byte limitation on error message lengths in the Nginx core. This limit includes trailing newlines and leading time stamps. If the message size exceeds this limit, Nginx will truncate the message text accordingly. This limit can be manually modified by editing the `NGX_MAX_ERROR_STR` macro definition in the `src/core/ngx_log.h` file in the Nginx source tree.

[Back to TOC](#nginx-api-for-lua)

ngx.ctx
-------

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, exit_worker_by_lua&#42;*

This table can be used to store per-request Lua context data and has a life time identical to the current request (as with the Nginx variables).

Consider the following example,

```nginx

 location /test {
     rewrite_by_lua_block {
         ngx.ctx.foo = 76
     }
     access_by_lua_block {
         ngx.ctx.foo = ngx.ctx.foo + 3
     }
     content_by_lua_block {
         ngx.say(ngx.ctx.foo)
     }
 }
```

Then `GET /test` will yield the output

```bash

 79
```

That is, the `ngx.ctx.foo` entry persists across the rewrite, access, and content phases of a request.

Every request, including subrequests, has its own copy of the table. For example:

```nginx

 location /sub {
     content_by_lua_block {
         ngx.say("sub pre: ", ngx.ctx.blah)
         ngx.ctx.blah = 32
         ngx.say("sub post: ", ngx.ctx.blah)
     }
 }

 location /main {
     content_by_lua_block {
         ngx.ctx.blah = 73
         ngx.say("main pre: ", ngx.ctx.blah)
         local res = ngx.location.capture("/sub")
         ngx.print(res.body)
         ngx.say("main post: ", ngx.ctx.blah)
     }
 }
```

Then `GET /main` will give the output

```bash

 main pre: 73
 sub pre: nil
 sub post: 32
 main post: 73
```

Here, modification of the `ngx.ctx.blah` entry in the subrequest does not affect the one in the parent request. This is because they have two separate versions of `ngx.ctx.blah`.

Internal redirects (triggered by nginx configuration directives like `error_page`, `try_files`, `index` and etc) will destroy the original request `ngx.ctx` data (if any) and the new request will have an empty `ngx.ctx` table. For instance,

```nginx

 location /new {
     content_by_lua_block {
         ngx.say(ngx.ctx.foo)
     }
 }

 location /orig {
     content_by_lua_block {
         ngx.ctx.foo = "hello"
         ngx.exec("/new")
     }
 }
```

Then `GET /orig` will give

```bash

 nil
```

rather than the original `"hello"` value.

Because HTTP request is created after SSL handshake, the `ngx.ctx` created
in [ssl_certificate_by_lua*](#ssl_certificate_by_lua), [ssl_session_store_by_lua*](#ssl_session_store_by_lua), [ssl_session_fetch_by_lua*](#ssl_session_fetch_by_lua) and [ssl_client_hello_by_lua*](#ssl_client_hello_by_lua)
is not available in the following phases like [rewrite_by_lua*](#rewrite_by_lua).

Since `v0.10.18`, the `ngx.ctx` created during a SSL handshake
will be inherited by the requests which share the same TCP connection established by the handshake.
Note that overwrite values in `ngx.ctx` in the http request phases (like `rewrite_by_lua*`) will only take affect in the current http request.

Arbitrary data values, including Lua closures and nested tables, can be inserted into this "magic" table. It also allows the registration of custom meta methods.

Overriding `ngx.ctx` with a new Lua table is also supported, for example,

```lua

 ngx.ctx = { foo = 32, bar = 54 }
```

When being used in the context of [init_worker_by_lua*](#init_worker_by_lua), this table just has the same lifetime of the current Lua handler.

The `ngx.ctx` lookup requires relatively expensive metamethod calls and it is much slower than explicitly passing per-request data along by your own function arguments. So do not abuse this API for saving your own function arguments because it usually has quite some performance impact.

Because of the metamethod magic, never "local" the `ngx.ctx` table outside your Lua function scope on the Lua module level due to [worker-level data sharing](#data-sharing-within-an-nginx-worker). For example, the following is bad:

```lua

 -- mymodule.lua
 local _M = {}

 -- the following line is bad since ngx.ctx is a per-request
 -- data while this <code>ctx</code> variable is on the Lua module level
 -- and thus is per-nginx-worker.
 local ctx = ngx.ctx

 function _M.main()
     ctx.foo = "bar"
 end

 return _M
```

Use the following instead:

```lua

 -- mymodule.lua
 local _M = {}

 function _M.main(ctx)
     ctx.foo = "bar"
 end

 return _M
```

That is, let the caller pass the `ctx` table explicitly via a function argument.

[Back to TOC](#nginx-api-for-lua)

ngx.location.capture
--------------------

**syntax:** *res = ngx.location.capture(uri, options?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Issues a synchronous but still non-blocking *Nginx Subrequest* using `uri`.

Nginx's subrequests provide a powerful way to make non-blocking internal requests to other locations configured with disk file directory or *any* other Nginx C modules like `ngx_proxy`, `ngx_fastcgi`, `ngx_memc`,
`ngx_postgres`, `ngx_drizzle`, and even ngx_lua itself and etc etc etc.

Also note that subrequests just mimic the HTTP interface but there is *no* extra HTTP/TCP traffic *nor* IPC involved. Everything works internally, efficiently, on the C level.

Subrequests are completely different from HTTP 301/302 redirection (via [ngx.redirect](#ngxredirect)) and internal redirection (via [ngx.exec](#ngxexec)).

You should always read the request body (by either calling [ngx.req.read_body](#ngxreqread_body) or configuring [lua_need_request_body](#lua_need_request_body) on) before initiating a subrequest.

This API function (as well as [ngx.location.capture_multi](#ngxlocationcapture_multi)) always buffers the whole response body of the subrequest in memory. Thus, you should use [cosockets](#ngxsockettcp)
and streaming processing instead if you have to handle large subrequest responses.

Here is a basic example:

```lua

 res = ngx.location.capture(uri)
```

Returns a Lua table with 4 slots: `res.status`, `res.header`, `res.body`, and `res.truncated`.

`res.status` holds the response status code for the subrequest response.

`res.header` holds all the response headers of the
subrequest and it is a normal Lua table. For multi-value response headers,
the value is a Lua (array) table that holds all the values in the order that
they appear. For instance, if the subrequest response headers contain the following
lines:

```bash

 Set-Cookie: a=3
 Set-Cookie: foo=bar
 Set-Cookie: baz=blah
```

Then `res.header["Set-Cookie"]` will be evaluated to the table value
`{"a=3", "foo=bar", "baz=blah"}`.

`res.body` holds the subrequest's response body data, which might be truncated. You always need to check the `res.truncated` boolean flag to see if `res.body` contains truncated data. The data truncation here can only be caused by those unrecoverable errors in your subrequests like the cases that the remote end aborts the connection prematurely in the middle of the response body data stream or a read timeout happens when your subrequest is receiving the response body data from the remote.

URI query strings can be concatenated to URI itself, for instance,

```lua

 res = ngx.location.capture('/foo/bar?a=3&b=4')
```

Named locations like `@foo` are not allowed due to a limitation in
the Nginx core. Use normal locations combined with the `internal` directive to
prepare internal-only locations.

An optional option table can be fed as the second
argument, which supports the options:

* `method`
	specify the subrequest's request method, which only accepts constants like `ngx.HTTP_POST`.
* `body`
	specify the subrequest's request body (string value only).
* `args`
	specify the subrequest's URI query arguments (both string value and Lua tables are accepted)
* `ctx`
	specify a Lua table to be the [ngx.ctx](#ngxctx) table for the subrequest. It can be the current request's [ngx.ctx](#ngxctx) table, which effectively makes the parent and its subrequest to share exactly the same context table. This option was first introduced in the `v0.3.1rc25` release.
* `vars`
	take a Lua table which holds the values to set the specified Nginx variables in the subrequest as this option's value. This option was first introduced in the `v0.3.1rc31` release.
* `copy_all_vars`
	specify whether to copy over all the Nginx variable values of the current request to the subrequest in question. modifications of the Nginx variables in the subrequest will not affect the current (parent) request. This option was first introduced in the `v0.3.1rc31` release.
* `share_all_vars`
	specify whether to share all the Nginx variables of the subrequest with the current (parent) request. modifications of the Nginx variables in the subrequest will affect the current (parent) request. Enabling this option may lead to hard-to-debug issues due to bad side-effects and is considered bad and harmful. Only enable this option when you completely know what you are doing.
* `always_forward_body`
	when set to true, the current (parent) request's request body will always be forwarded to the subrequest being created if the `body` option is not specified. The request body read by either [ngx.req.read_body()](#ngxreqread_body) or [lua_need_request_body on](#lua_need_request_body) will be directly forwarded to the subrequest without copying the whole request body data when creating the subrequest (no matter the request body data is buffered in memory buffers or temporary files). By default, this option is `false` and when the `body` option is not specified, the request body of the current (parent) request is only forwarded when the subrequest takes the `PUT` or `POST` request method.

Issuing a POST subrequest, for example, can be done as follows

```lua

 res = ngx.location.capture(
     '/foo/bar',
     { method = ngx.HTTP_POST, body = 'hello, world' }
 )
```

See HTTP method constants methods other than POST.
The `method` option is `ngx.HTTP_GET` by default.

The `args` option can specify extra URI arguments, for instance,

```lua

 ngx.location.capture('/foo?a=1',
     { args = { b = 3, c = ':' } }
 )
```

is equivalent to

```lua

 ngx.location.capture('/foo?a=1&b=3&c=%3a')
```

that is, this method will escape argument keys and values according to URI rules and
concatenate them together into a complete query string. The format for the Lua table passed as the `args` argument is identical to the format used in the [ngx.encode_args](#ngxencode_args) method.

The `args` option can also take plain query strings:

```lua

 ngx.location.capture('/foo?a=1',
     { args = 'b=3&c=%3a' }
 )
```

This is functionally identical to the previous examples.

The `share_all_vars` option controls whether to share Nginx variables among the current request and its subrequests.
If this option is set to `true`, then the current request and associated subrequests will share the same Nginx variable scope. Hence, changes to Nginx variables made by a subrequest will affect the current request.

Care should be taken in using this option as variable scope sharing can have unexpected side effects. The `args`, `vars`, or `copy_all_vars` options are generally preferable instead.

This option is set to `false` by default

```nginx

 location /other {
     set $dog "$dog world";
     echo "$uri dog: $dog";
 }

 location /lua {
     set $dog 'hello';
     content_by_lua_block {
         res = ngx.location.capture("/other",
             { share_all_vars = true })

         ngx.print(res.body)
         ngx.say(ngx.var.uri, ": ", ngx.var.dog)
     }
 }
```

Accessing location `/lua` gives


    /other dog: hello world
    /lua: hello world


The `copy_all_vars` option provides a copy of the parent request's Nginx variables to subrequests when such subrequests are issued. Changes made to these variables by such subrequests will not affect the parent request or any other subrequests sharing the parent request's variables.

```nginx

 location /other {
     set $dog "$dog world";
     echo "$uri dog: $dog";
 }

 location /lua {
     set $dog 'hello';
     content_by_lua_block {
         res = ngx.location.capture("/other",
             { copy_all_vars = true })

         ngx.print(res.body)
         ngx.say(ngx.var.uri, ": ", ngx.var.dog)
     }
 }
```

Request `GET /lua` will give the output


    /other dog: hello world
    /lua: hello


Note that if both `share_all_vars` and `copy_all_vars` are set to true, then `share_all_vars` takes precedence.

In addition to the two settings above, it is possible to specify
values for variables in the subrequest using the `vars` option. These
variables are set after the sharing or copying of variables has been
evaluated, and provides a more efficient method of passing specific
values to a subrequest over encoding them as URL arguments and
unescaping them in the Nginx config file.

```nginx

 location /other {
     content_by_lua_block {
         ngx.say("dog = ", ngx.var.dog)
         ngx.say("cat = ", ngx.var.cat)
     }
 }

 location /lua {
     set $dog '';
     set $cat '';
     content_by_lua_block {
         res = ngx.location.capture("/other",
             { vars = { dog = "hello", cat = 32 }})

         ngx.print(res.body)
     }
 }
```

Accessing `/lua` will yield the output


    dog = hello
    cat = 32


The `ctx` option can be used to specify a custom Lua table to serve as the [ngx.ctx](#ngxctx) table for the subrequest.

```nginx

 location /sub {
     content_by_lua_block {
         ngx.ctx.foo = "bar";
     }
 }
 location /lua {
     content_by_lua_block {
         local ctx = {}
         res = ngx.location.capture("/sub", { ctx = ctx })

         ngx.say(ctx.foo)
         ngx.say(ngx.ctx.foo)
     }
 }
```

Then request `GET /lua` gives


    bar
    nil


It is also possible to use this `ctx` option to share the same [ngx.ctx](#ngxctx) table between the current (parent) request and the subrequest:

```nginx

 location /sub {
     content_by_lua_block {
         ngx.ctx.foo = "bar"
     }
 }
 location /lua {
     content_by_lua_block {
         res = ngx.location.capture("/sub", { ctx = ngx.ctx })
         ngx.say(ngx.ctx.foo)
     }
 }
```

Request `GET /lua` yields the output


    bar


Note that subrequests issued by [ngx.location.capture](#ngxlocationcapture) inherit all the
request headers of the current request by default and that this may have unexpected side effects on the
subrequest responses. For example, when using the standard `ngx_proxy` module to serve
subrequests, an "Accept-Encoding: gzip" header in the main request may result
in gzipped responses that cannot be handled properly in Lua code. Original request headers should be ignored by setting
[proxy_pass_request_headers](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass_request_headers) to `off` in subrequest locations.

When the `body` option is not specified and the `always_forward_body` option is false (the default value), the `POST` and `PUT` subrequests will inherit the request bodies of the parent request (if any).

There is a hard-coded upper limit on the number of subrequests possible for every main request. In older versions of Nginx, the limit was `50` concurrent subrequests and in more recent versions, Nginx `1.9.5` onwards, the same limit is changed to limit the depth of recursive subrequests. When this limit is exceeded, the following error message is added to the `error.log` file:


    [error] 13983#0: *1 subrequests cycle while processing "/uri"


The limit can be manually modified if required by editing the definition of the `NGX_HTTP_MAX_SUBREQUESTS` macro in the `nginx/src/http/ngx_http_request.h` file in the Nginx source tree.

Please also refer to restrictions on capturing locations configured by [subrequest directives of other modules](#locations-configured-by-subrequest-directives-of-other-modules).

[Back to TOC](#nginx-api-for-lua)

ngx.location.capture_multi
--------------------------

**syntax:** *res1, res2, ... = ngx.location.capture_multi({ {uri, options?}, {uri, options?}, ... })*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Just like [ngx.location.capture](#ngxlocationcapture), but supports multiple subrequests running in parallel.

This function issues several parallel subrequests specified by the input table and returns their results in the same order. For example,

```lua

 res1, res2, res3 = ngx.location.capture_multi{
     { "/foo", { args = "a=3&b=4" } },
     { "/bar" },
     { "/baz", { method = ngx.HTTP_POST, body = "hello" } },
 }

 if res1.status == ngx.HTTP_OK then
     ...
 end

 if res2.body == "BLAH" then
     ...
 end
```

This function will not return until all the subrequests terminate.
The total latency is the longest latency of the individual subrequests rather than the sum.

Lua tables can be used for both requests and responses when the number of subrequests to be issued is not known in advance:

```lua

 -- construct the requests table
 local reqs = {}
 table.insert(reqs, { "/mysql" })
 table.insert(reqs, { "/postgres" })
 table.insert(reqs, { "/redis" })
 table.insert(reqs, { "/memcached" })

 -- issue all the requests at once and wait until they all return
 local resps = {
     ngx.location.capture_multi(reqs)
 }

 -- loop over the responses table
 for i, resp in ipairs(resps) do
     -- process the response table "resp"
 end
```

The [ngx.location.capture](#ngxlocationcapture) function is just a special form
of this function. Logically speaking, the [ngx.location.capture](#ngxlocationcapture) can be implemented like this

```lua

 ngx.location.capture =
     function (uri, args)
         return ngx.location.capture_multi({ {uri, args} })
     end
```

Please also refer to restrictions on capturing locations configured by [subrequest directives of other modules](#locations-configured-by-subrequest-directives-of-other-modules).

[Back to TOC](#nginx-api-for-lua)

ngx.status
----------

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Read and write the current request's response status. This should be called
before sending out the response headers.

```lua

 ngx.status = ngx.HTTP_CREATED
 status = ngx.status
```

Setting `ngx.status` after the response header is sent out has no effect but leaving an error message in your Nginx's error log file:


    attempt to set ngx.status after sending out response headers


[Back to TOC](#nginx-api-for-lua)

ngx.header.HEADER
-----------------

**syntax:** *ngx.header.HEADER = VALUE*

**syntax:** *value = ngx.header.HEADER*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Set, add to, or clear the current request's `HEADER` response header that is to be sent.

Underscores (`_`) in the header names will be replaced by hyphens (`-`) by default. This transformation can be turned off via the [lua_transform_underscores_in_response_headers](#lua_transform_underscores_in_response_headers) directive.

The header names are matched case-insensitively.

```lua

 -- equivalent to ngx.header["Content-Type"] = 'text/plain'
 ngx.header.content_type = 'text/plain'

 ngx.header["X-My-Header"] = 'blah blah'
```

Multi-value headers can be set this way:

```lua

 ngx.header['Set-Cookie'] = {'a=32; path=/', 'b=4; path=/'}
```

will yield

```bash

 Set-Cookie: a=32; path=/
 Set-Cookie: b=4; path=/
```

in the response headers.

Only Lua tables are accepted (Only the last element in the table will take effect for standard headers such as `Content-Type` that only accept a single value).

```lua

 ngx.header.content_type = {'a', 'b'}
```

is equivalent to

```lua

 ngx.header.content_type = 'b'
```

Setting a slot to `nil` effectively removes it from the response headers:

```lua

 ngx.header["X-My-Header"] = nil
```

The same applies to assigning an empty table:

```lua

 ngx.header["X-My-Header"] = {}
```

Setting `ngx.header.HEADER` after sending out response headers (either explicitly with [ngx.send_headers](#ngxsend_headers) or implicitly with [ngx.print](#ngxprint) and similar) will log an error message.

Reading `ngx.header.HEADER` will return the value of the response header named `HEADER`.

Underscores (`_`) in the header names will also be replaced by dashes (`-`) and the header names will be matched case-insensitively. If the response header is not present at all, `nil` will be returned.

This is particularly useful in the context of [header_filter_by_lua*](#header_filter_by_lua), for example,

```nginx

 location /test {
     set $footer '';

     proxy_pass http://some-backend;

     header_filter_by_lua_block {
         if ngx.header["X-My-Header"] == "blah" then
             ngx.var.footer = "some value"
         end
     }

     echo_after_body $footer;
 }
```

For multi-value headers, all of the values of header will be collected in order and returned as a Lua table. For example, response headers


    Foo: bar
    Foo: baz


will result in

```lua

 {"bar", "baz"}
```

to be returned when reading `ngx.header.Foo`.

Note that `ngx.header` is not a normal Lua table and as such, it is not possible to iterate through it using the Lua `ipairs` function.

Note: this function throws a Lua error if `HEADER` or
`VALUE` contain unsafe characters (control characters).

For reading *request* headers, use the [ngx.req.get_headers](#ngxreqget_headers) function instead.

[Back to TOC](#nginx-api-for-lua)

ngx.resp.get_headers
--------------------

**syntax:** *headers, err = ngx.resp.get_headers(max_headers?, raw?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, balancer_by_lua&#42;*

Returns a Lua table holding all the current response headers for the current request.

```lua

 local h, err = ngx.resp.get_headers()

 if err == "truncated" then
     -- one can choose to ignore or reject the current response here
 end

 for k, v in pairs(h) do
     ...
 end
```

This function has the same signature as [ngx.req.get_headers](#ngxreqget_headers) except getting response headers instead of request headers.

Note that a maximum of 100 response headers are parsed by default (including those with the same name) and that additional response headers are silently discarded to guard against potential denial of service attacks. Since `v0.10.13`, when the limit is exceeded, it will return a second value which is the string `"truncated"`.

This API was first introduced in the `v0.9.5` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.is_internal
-------------------

**syntax:** *is_internal = ngx.req.is_internal()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Returns a boolean indicating whether the current request is an "internal request", i.e.,
a request initiated from inside the current Nginx server instead of from the client side.

Subrequests are all internal requests and so are requests after internal redirects.

This API was first introduced in the `v0.9.20` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.start_time
------------------

**syntax:** *secs = ngx.req.start_time()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Returns a floating-point number representing the timestamp (including milliseconds as the decimal part) when the current request was created.

The following example emulates the `$request_time` variable value (provided by [ngx_http_log_module](http://nginx.org/en/docs/http/ngx_http_log_module.html)) in pure Lua:

```lua

 local request_time = ngx.now() - ngx.req.start_time()
```

This function was first introduced in the `v0.7.7` release.

See also [ngx.now](#ngxnow) and [ngx.update_time](#ngxupdate_time).

[Back to TOC](#nginx-api-for-lua)

ngx.req.http_version
--------------------

**syntax:** *num = ngx.req.http_version()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;*

Returns the HTTP version number for the current request as a Lua number.

Current possible values are 2.0, 1.0, 1.1, and 0.9. Returns `nil` for unrecognized values.

This method was first introduced in the `v0.7.17` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.raw_header
------------------

**syntax:** *str = ngx.req.raw_header(no_request_line?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;*

Returns the original raw HTTP protocol header received by the Nginx server.

By default, the request line and trailing `CR LF` terminator will also be included. For example,

```lua

 ngx.print(ngx.req.raw_header())
```

gives something like this:


    GET /t HTTP/1.1
    Host: localhost
    Connection: close
    Foo: bar



You can specify the optional
`no_request_line` argument as a `true` value to exclude the request line from the result. For example,

```lua

 ngx.print(ngx.req.raw_header(true))
```

outputs something like this:


    Host: localhost
    Connection: close
    Foo: bar



This method was first introduced in the `v0.7.17` release.

This method does not work in HTTP/2 requests yet.

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_method
------------------

**syntax:** *method_name = ngx.req.get_method()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, balancer_by_lua&#42;, log_by_lua&#42;*

Retrieves the current request's request method name. Strings like `"GET"` and `"POST"` are returned instead of numerical [method constants](#http-method-constants).

If the current request is an Nginx subrequest, then the subrequest's method name will be returned.

This method was first introduced in the `v0.5.6` release.

See also [ngx.req.set_method](#ngxreqset_method).

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_method
------------------

**syntax:** *ngx.req.set_method(method_id)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;*

Overrides the current request's request method with the `method_id` argument. Currently only numerical [method constants](#http-method-constants) are supported, like `ngx.HTTP_POST` and `ngx.HTTP_GET`.

If the current request is an Nginx subrequest, then the subrequest's method will be overridden.

This method was first introduced in the `v0.5.6` release.

See also [ngx.req.get_method](#ngxreqget_method).

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_uri
---------------

**syntax:** *ngx.req.set_uri(uri, jump?, binary?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;*

Rewrite the current request's (parsed) URI by the `uri` argument. The `uri` argument must be a Lua string and cannot be of zero length, or a Lua exception will be thrown.

The optional boolean `jump` argument can trigger location rematch (or location jump) as [ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html)'s [rewrite](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite) directive, that is, when `jump` is `true` (default to `false`), this function will never return and it will tell Nginx to try re-searching locations with the new URI value at the later `post-rewrite` phase and jumping to the new location.

Location jump will not be triggered otherwise, and only the current request's URI will be modified, which is also the default behavior. This function will return but with no returned values when the `jump` argument is `false` or absent altogether.

For example, the following Nginx config snippet

```nginx

 rewrite ^ /foo last;
```

can be coded in Lua like this:

```lua

 ngx.req.set_uri("/foo", true)
```

Similarly, Nginx config

```nginx

 rewrite ^ /foo break;
```

can be coded in Lua as

```lua

 ngx.req.set_uri("/foo", false)
```

or equivalently,

```lua

 ngx.req.set_uri("/foo")
```

The `jump` argument can only be set to `true` in [rewrite_by_lua*](#rewrite_by_lua). Use of jump in other contexts is prohibited and will throw out a Lua exception.

A more sophisticated example involving regex substitutions is as follows

```nginx

 location /test {
     rewrite_by_lua_block {
         local uri = ngx.re.sub(ngx.var.uri, "^/test/(.*)", "/$1", "o")
         ngx.req.set_uri(uri)
     }
     proxy_pass http://my_backend;
 }
```

which is functionally equivalent to

```nginx

 location /test {
     rewrite ^/test/(.*) /$1 break;
     proxy_pass http://my_backend;
 }
```

Note: this function throws a Lua error if the `uri` argument
contains unsafe characters (control characters).

Note that it is not possible to use this interface to rewrite URI arguments and that [ngx.req.set_uri_args](#ngxreqset_uri_args) should be used for this instead. For instance, Nginx config

```nginx

 rewrite ^ /foo?a=3? last;
```

can be coded as

```nginx

 ngx.req.set_uri_args("a=3")
 ngx.req.set_uri("/foo", true)
```

or

```nginx

 ngx.req.set_uri_args({a = 3})
 ngx.req.set_uri("/foo", true)
```

Starting from `0.10.16` of this module, this function accepts an
optional boolean `binary` argument to allow arbitrary binary URI
data. By default, this `binary` argument is false and this function
will throw out a Lua error such as the one below when the `uri`
argument contains any control characters (ASCII Code 0 ~ 0x08, 0x0A ~ 0x1F and 0x7F).


    [error] 23430#23430: *1 lua entry thread aborted: runtime error:
    content_by_lua(nginx.conf:44):3: ngx.req.set_uri unsafe byte "0x00"
    in "\x00foo" (maybe you want to set the 'binary' argument?)


This interface was first introduced in the `v0.3.1rc14` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_uri_args
--------------------

**syntax:** *ngx.req.set_uri_args(args)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;*

Rewrite the current request's URI query arguments by the `args` argument. The `args` argument can be either a Lua string, as in

```lua

 ngx.req.set_uri_args("a=3&b=hello%20world")
```

or a Lua table holding the query arguments' key-value pairs, as in

```lua

 ngx.req.set_uri_args({ a = 3, b = "hello world" })
```

In the former case, i.e., when the whole query-string is provided directly,
the input Lua string should already be well-formed with the URI encoding.
For security considerations, this method will automatically escape any control and
whitespace characters (ASCII code 0x00 ~ 0x20 and 0x7F) in the Lua string.

In the latter case, this method will escape argument keys and values according to the URI escaping rule.

Multi-value arguments are also supported:

```lua

 ngx.req.set_uri_args({ a = 3, b = {5, 6} })
```

which will result in a query string like `a=3&b=5&b=6` or `b=5&b=6&a=3`.

**Note that when using Lua table as the `arg` argument, the order of the arguments in the result query string which change from time to time. If you would like to get an ordered result, you need to use Lua string as the `arg` argument.**

This interface was first introduced in the `v0.3.1rc13` release.

See also [ngx.req.set_uri](#ngxreqset_uri).

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_uri_args
--------------------

**syntax:** *args, err = ngx.req.get_uri_args(max_args?, tab?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, balancer_by_lua&#42;*

Returns a Lua table holding all the current request URL query arguments. An optional `tab` argument
can be used to reuse the table returned by this method.

```nginx

 location = /test {
     content_by_lua_block {
         local args, err = ngx.req.get_uri_args()

         if err == "truncated" then
             -- one can choose to ignore or reject the current request here
         end

         for key, val in pairs(args) do
             if type(val) == "table" then
                 ngx.say(key, ": ", table.concat(val, ", "))
             else
                 ngx.say(key, ": ", val)
             end
         end
     }
 }
```

Then `GET /test?foo=bar&bar=baz&bar=blah` will yield the response body

```bash

 foo: bar
 bar: baz, blah
```

Multiple occurrences of an argument key will result in a table value holding all the values for that key in order.

Keys and values are unescaped according to URI escaping rules. In the settings above, `GET /test?a%20b=1%61+2` will yield:

```bash

 a b: 1a 2
```

Arguments without the `=<value>` parts are treated as boolean arguments. `GET /test?foo&bar` will yield:

```bash

 foo: true
 bar: true
```

That is, they will take Lua boolean values `true`. However, they are different from arguments taking empty string values. `GET /test?foo=&bar=` will give something like

```bash

 foo:
 bar:
```

Empty key arguments are discarded. `GET /test?=hello&=world` will yield an empty output for instance.

Updating query arguments via the Nginx variable `$args` (or `ngx.var.args` in Lua) at runtime is also supported:

```lua

 ngx.var.args = "a=3&b=42"
 local args, err = ngx.req.get_uri_args()
```

Here the `args` table will always look like

```lua

 {a = 3, b = 42}
```

regardless of the actual request query string.

Note that a maximum of 100 request arguments are parsed by default (including those with the same name) and that additional request arguments are silently discarded to guard against potential denial of service attacks. Since `v0.10.13`, when the limit is exceeded, it will return a second value which is the string `"truncated"`.

However, the optional `max_args` function argument can be used to override this limit:

```lua

 local args, err = ngx.req.get_uri_args(10)
 if err == "truncated" then
     -- one can choose to ignore or reject the current request here
 end
```

This argument can be set to zero to remove the limit and to process all request arguments received:

```lua

 local args, err = ngx.req.get_uri_args(0)
```

Removing the `max_args` cap is strongly discouraged.

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_post_args
---------------------

**syntax:** *args, err = ngx.req.get_post_args(max_args?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Returns a Lua table holding all the current request POST query arguments (of the MIME type `application/x-www-form-urlencoded`). Call [ngx.req.read_body](#ngxreqread_body) to read the request body first or turn on the [lua_need_request_body](#lua_need_request_body) directive to avoid errors.

```nginx

 location = /test {
     content_by_lua_block {
         ngx.req.read_body()
         local args, err = ngx.req.get_post_args()

         if err == "truncated" then
             -- one can choose to ignore or reject the current request here
         end

         if not args then
             ngx.say("failed to get post args: ", err)
             return
         end
         for key, val in pairs(args) do
             if type(val) == "table" then
                 ngx.say(key, ": ", table.concat(val, ", "))
             else
                 ngx.say(key, ": ", val)
             end
         end
     }
 }
```

Then

```bash

 # Post request with the body 'foo=bar&bar=baz&bar=blah'
 $ curl --data 'foo=bar&bar=baz&bar=blah' localhost/test
```

will yield the response body like

```bash

 foo: bar
 bar: baz, blah
```

Multiple occurrences of an argument key will result in a table value holding all of the values for that key in order.

Keys and values will be unescaped according to URI escaping rules.

With the settings above,

```bash

 # POST request with body 'a%20b=1%61+2'
 $ curl -d 'a%20b=1%61+2' localhost/test
```

will yield:

```bash

 a b: 1a 2
```

Arguments without the `=<value>` parts are treated as boolean arguments. `POST /test` with the request body `foo&bar` will yield:

```bash

 foo: true
 bar: true
```

That is, they will take Lua boolean values `true`. However, they are different from arguments taking empty string values. `POST /test` with request body `foo=&bar=` will return something like

```bash

 foo:
 bar:
```

Empty key arguments are discarded. `POST /test` with body `=hello&=world` will yield empty outputs for instance.

Note that a maximum of 100 request arguments are parsed by default (including those with the same name) and that additional request arguments are silently discarded to guard against potential denial of service attacks. Since `v0.10.13`, when the limit is exceeded, it will return a second value which is the string `"truncated"`.

However, the optional `max_args` function argument can be used to override this limit:

```lua

 local args, err = ngx.req.get_post_args(10)
 if err == "truncated" then
     -- one can choose to ignore or reject the current request here
 end
```

This argument can be set to zero to remove the limit and to process all request arguments received:

```lua

 local args, err = ngx.req.get_post_args(0)
```

Removing the `max_args` cap is strongly discouraged.

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_headers
-------------------

**syntax:** *headers, err = ngx.req.get_headers(max_headers?, raw?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Returns a Lua table holding all the current request headers.

```lua

 local h, err = ngx.req.get_headers()

 if err == "truncated" then
     -- one can choose to ignore or reject the current request here
 end

 for k, v in pairs(h) do
     ...
 end
```

To read an individual header:

```lua

 ngx.say("Host: ", ngx.req.get_headers()["Host"])
```

Note that the [ngx.var.HEADER](#ngxvarvariable) API call, which uses core [$http_HEADER](http://nginx.org/en/docs/http/ngx_http_core_module.html#var_http_) variables, may be more preferable for reading individual request headers.

For multiple instances of request headers such as:

```bash

 Foo: foo
 Foo: bar
 Foo: baz
```

the value of `ngx.req.get_headers()["Foo"]` will be a Lua (array) table such as:

```lua

 {"foo", "bar", "baz"}
```

Note that a maximum of 100 request headers are parsed by default (including those with the same name) and that additional request headers are silently discarded to guard against potential denial of service attacks. Since `v0.10.13`, when the limit is exceeded, it will return a second value which is the string `"truncated"`.

However, the optional `max_headers` function argument can be used to override this limit:

```lua

 local headers, err = ngx.req.get_headers(10)

 if err == "truncated" then
     -- one can choose to ignore or reject the current request here
 end
```

This argument can be set to zero to remove the limit and to process all request headers received:

```lua

 local headers, err = ngx.req.get_headers(0)
```

Removing the `max_headers` cap is strongly discouraged.

Since the `0.6.9` release, all the header names in the Lua table returned are converted to the pure lower-case form by default, unless the `raw` argument is set to `true` (default to `false`).

Also, by default, an `__index` metamethod is added to the resulting Lua table and will normalize the keys to a pure lowercase form with all underscores converted to dashes in case of a lookup miss. For example, if a request header `My-Foo-Header` is present, then the following invocations will all pick up the value of this header correctly:

```lua

 ngx.say(headers.my_foo_header)
 ngx.say(headers["My-Foo-Header"])
 ngx.say(headers["my-foo-header"])
```

The `__index` metamethod will not be added when the `raw` argument is set to `true`.

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_header
------------------

**syntax:** *ngx.req.set_header(header_name, header_value)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;*

Set the current request's request header named `header_name` to value `header_value`, overriding any existing ones.

The input Lua string `header_name` and `header_value` should already be well-formed with the URI encoding.
For security considerations, this method will automatically escape " ", """, "(", ")", ",", "/", ":", ";", "?",
"<", "=", ">", "?", "@", "[", "]", "\", "{", "}", 0x00-0x1F, 0x7F-0xFF in `header_name` and automatically escape
"0x00-0x08, 0x0A-0x0F, 0x7F in `header_value`.

By default, all the subrequests subsequently initiated by [ngx.location.capture](#ngxlocationcapture) and [ngx.location.capture_multi](#ngxlocationcapture_multi) will inherit the new header.

It is not a Lua's equivalent of nginx `proxy_set_header` directive (same is true about [ngx.req.clear_header](#ngxreqclear_header)). `proxy_set_header` only affects the upstream request while `ngx.req.set_header` change the incoming request. Record the http headers in the access log file will show the difference. But you still can use it as an alternative of nginx `proxy_set_header` directive as long as you know the difference.

Here is an example of setting the `Content-Type` header:

```lua

 ngx.req.set_header("Content-Type", "text/css")
```

The `header_value` can take an array list of values,
for example,

```lua

 ngx.req.set_header("Foo", {"a", "abc"})
```

will produce two new request headers:

```bash

 Foo: a
 Foo: abc
```

and old `Foo` headers will be overridden if there is any.

When the `header_value` argument is `nil`, the request header will be removed. So

```lua

 ngx.req.set_header("X-Foo", nil)
```

is equivalent to

```lua

 ngx.req.clear_header("X-Foo")
```

Note: this function throws a Lua error if `header_name` or
`header_value` contain unsafe characters (control characters).

[Back to TOC](#nginx-api-for-lua)

ngx.req.clear_header
--------------------

**syntax:** *ngx.req.clear_header(header_name)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;*

Clears the current request's request header named `header_name`. None of the current request's existing subrequests will be affected but subsequently initiated subrequests will inherit the change by default.

[Back to TOC](#nginx-api-for-lua)

ngx.req.read_body
-----------------

**syntax:** *ngx.req.read_body()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Reads the client request body synchronously without blocking the Nginx event loop.

```lua

 ngx.req.read_body()
 local args = ngx.req.get_post_args()
```

If the request body is already read previously by turning on [lua_need_request_body](#lua_need_request_body) or by using other modules, then this function does not run and returns immediately.

If the request body has already been explicitly discarded, either by the [ngx.req.discard_body](#ngxreqdiscard_body) function or other modules, this function does not run and returns immediately.

In case of errors, such as connection errors while reading the data, this method will throw out a Lua exception *or* terminate the current request with a 500 status code immediately.

The request body data read using this function can be retrieved later via [ngx.req.get_body_data](#ngxreqget_body_data) or, alternatively, the temporary file name for the body data cached to disk using [ngx.req.get_body_file](#ngxreqget_body_file). This depends on

1. whether the current request body is already larger than the [client_body_buffer_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size),
1. and whether [client_body_in_file_only](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_in_file_only) has been switched on.

In cases where current request may have a request body and the request body data is not required, The [ngx.req.discard_body](#ngxreqdiscard_body) function must be used to explicitly discard the request body to avoid breaking things under HTTP 1.1 keepalive or HTTP 1.1 pipelining.

This function was first introduced in the `v0.3.1rc17` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.discard_body
--------------------

**syntax:** *ngx.req.discard_body()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Explicitly discard the request body, i.e., read the data on the connection and throw it away immediately (without using the request body by any means).

This function is an asynchronous call and returns immediately.

If the request body has already been read, this function does nothing and returns immediately.

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.read_body](#ngxreqread_body).

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_body_data
---------------------

**syntax:** *data = ngx.req.get_body_data()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, log_by_lua&#42;*

Retrieves in-memory request body data. It returns a Lua string rather than a Lua table holding all the parsed query arguments. Use the [ngx.req.get_post_args](#ngxreqget_post_args) function instead if a Lua table is required.

This function returns `nil` if

1. the request body has not been read,
1. the request body has been read into disk temporary files,
1. or the request body has zero size.

If the request body has not been read yet, call [ngx.req.read_body](#ngxreqread_body) first (or turn on [lua_need_request_body](#lua_need_request_body) to force this module to read the request body. This is not recommended however).

If the request body has been read into disk files, try calling the [ngx.req.get_body_file](#ngxreqget_body_file) function instead.

To force in-memory request bodies, try setting [client_body_buffer_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size) to the same size value in [client_max_body_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size).

Note that calling this function instead of using `ngx.var.request_body` or `ngx.var.echo_request_body` is more efficient because it can save one dynamic memory allocation and one data copy.

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.get_body_file](#ngxreqget_body_file).

[Back to TOC](#nginx-api-for-lua)

ngx.req.get_body_file
---------------------

**syntax:** *file_name = ngx.req.get_body_file()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Retrieves the file name for the in-file request body data. Returns `nil` if the request body has not been read or has been read into memory.

The returned file is read only and is usually cleaned up by Nginx's memory pool. It should not be manually modified, renamed, or removed in Lua code.

If the request body has not been read yet, call [ngx.req.read_body](#ngxreqread_body) first (or turn on [lua_need_request_body](#lua_need_request_body) to force this module to read the request body. This is not recommended however).

If the request body has been read into memory, try calling the [ngx.req.get_body_data](#ngxreqget_body_data) function instead.

To force in-file request bodies, try turning on [client_body_in_file_only](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_in_file_only).

This function was first introduced in the `v0.3.1rc17` release.

See also [ngx.req.get_body_data](#ngxreqget_body_data).

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_body_data
---------------------

**syntax:** *ngx.req.set_body_data(data)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Set the current request's request body using the in-memory data specified by the `data` argument.

If the request body has not been read yet, call [ngx.req.read_body](#ngxreqread_body) first (or turn on [lua_need_request_body](#lua_need_request_body) to force this module to read the request body. This is not recommended however). Additionally, the request body must not have been previously discarded by [ngx.req.discard_body](#ngxreqdiscard_body).

Whether the previous request body has been read into memory or buffered into a disk file, it will be freed or the disk file will be cleaned up immediately, respectively.

This function was first introduced in the `v0.3.1rc18` release.

See also [ngx.req.set_body_file](#ngxreqset_body_file).

[Back to TOC](#nginx-api-for-lua)

ngx.req.set_body_file
---------------------

**syntax:** *ngx.req.set_body_file(file_name, auto_clean?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Set the current request's request body using the in-file data specified by the `file_name` argument.

If the request body has not been read yet, call [ngx.req.read_body](#ngxreqread_body) first (or turn on [lua_need_request_body](#lua_need_request_body) to force this module to read the request body. This is not recommended however). Additionally, the request body must not have been previously discarded by [ngx.req.discard_body](#ngxreqdiscard_body).

If the optional `auto_clean` argument is given a `true` value, then this file will be removed at request completion or the next time this function or [ngx.req.set_body_data](#ngxreqset_body_data) are called in the same request. The `auto_clean` is default to `false`.

Please ensure that the file specified by the `file_name` argument exists and is readable by an Nginx worker process by setting its permission properly to avoid Lua exception errors.

Whether the previous request body has been read into memory or buffered into a disk file, it will be freed or the disk file will be cleaned up immediately, respectively.

This function was first introduced in the `v0.3.1rc18` release.

See also [ngx.req.set_body_data](#ngxreqset_body_data).

[Back to TOC](#nginx-api-for-lua)

ngx.req.init_body
-----------------

**syntax:** *ngx.req.init_body(buffer_size?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Creates a new blank request body for the current request and initializes the buffer for later request body data writing via the [ngx.req.append_body](#ngxreqappend_body) and [ngx.req.finish_body](#ngxreqfinish_body) APIs.

If the `buffer_size` argument is specified, then its value will be used for the size of the memory buffer for body writing with [ngx.req.append_body](#ngxreqappend_body). If the argument is omitted, then the value specified by the standard [client_body_buffer_size](http://nginx.org/en/docs/http/ngx_http_core_module.html#client_body_buffer_size) directive will be used instead.

When the data can no longer be hold in the memory buffer for the request body, then the data will be flushed onto a temporary file just like the standard request body reader in the Nginx core.

It is important to always call the [ngx.req.finish_body](#ngxreqfinish_body) after all the data has been appended onto the current request body. Also, when this function is used together with [ngx.req.socket](#ngxreqsocket), it is required to call [ngx.req.socket](#ngxreqsocket) *before* this function, or you will get the "request body already exists" error message.

The usage of this function is often like this:

```lua

 ngx.req.init_body(128 * 1024)  -- buffer is 128KB
 for chunk in next_data_chunk() do
     ngx.req.append_body(chunk) -- each chunk can be 4KB
 end
 ngx.req.finish_body()
```

This function can be used with [ngx.req.append_body](#ngxreqappend_body), [ngx.req.finish_body](#ngxreqfinish_body), and [ngx.req.socket](#ngxreqsocket) to implement efficient input filters in pure Lua (in the context of [rewrite_by_lua*](#rewrite_by_lua) or [access_by_lua*](#access_by_lua)), which can be used with other Nginx content handler or upstream modules like [ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html) and [ngx_http_fastcgi_module](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html).

This function was first introduced in the `v0.5.11` release.

[Back to TOC](#nginx-api-for-lua)

ngx.req.append_body
-------------------

**syntax:** *ngx.req.append_body(data_chunk)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Append new data chunk specified by the `data_chunk` argument onto the existing request body created by the [ngx.req.init_body](#ngxreqinit_body) call.

When the data can no longer be hold in the memory buffer for the request body, then the data will be flushed onto a temporary file just like the standard request body reader in the Nginx core.

It is important to always call the [ngx.req.finish_body](#ngxreqfinish_body) after all the data has been appended onto the current request body.

This function can be used with [ngx.req.init_body](#ngxreqinit_body), [ngx.req.finish_body](#ngxreqfinish_body), and [ngx.req.socket](#ngxreqsocket) to implement efficient input filters in pure Lua (in the context of [rewrite_by_lua*](#rewrite_by_lua) or [access_by_lua*](#access_by_lua)), which can be used with other Nginx content handler or upstream modules like [ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html) and [ngx_http_fastcgi_module](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html).

This function was first introduced in the `v0.5.11` release.

See also [ngx.req.init_body](#ngxreqinit_body).

[Back to TOC](#nginx-api-for-lua)

ngx.req.finish_body
-------------------

**syntax:** *ngx.req.finish_body()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Completes the construction process of the new request body created by the [ngx.req.init_body](#ngxreqinit_body) and [ngx.req.append_body](#ngxreqappend_body) calls.

This function can be used with [ngx.req.init_body](#ngxreqinit_body), [ngx.req.append_body](#ngxreqappend_body), and [ngx.req.socket](#ngxreqsocket) to implement efficient input filters in pure Lua (in the context of [rewrite_by_lua*](#rewrite_by_lua) or [access_by_lua*](#access_by_lua)), which can be used with other Nginx content handler or upstream modules like [ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html) and [ngx_http_fastcgi_module](http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html).

This function was first introduced in the `v0.5.11` release.

See also [ngx.req.init_body](#ngxreqinit_body).

[Back to TOC](#nginx-api-for-lua)

ngx.req.socket
--------------

**syntax:** *tcpsock, err = ngx.req.socket()*

**syntax:** *tcpsock, err = ngx.req.socket(raw)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Returns a read-only cosocket object that wraps the downstream connection. Only [receive](#tcpsockreceive), [receiveany](#tcpsockreceiveany) and [receiveuntil](#tcpsockreceiveuntil) methods are supported on this object.

In case of error, `nil` will be returned as well as a string describing the error.

The socket object returned by this method is usually used to read the current request's body in a streaming fashion. Do not turn on the [lua_need_request_body](#lua_need_request_body) directive, and do not mix this call with [ngx.req.read_body](#ngxreqread_body) and [ngx.req.discard_body](#ngxreqdiscard_body).

If any request body data has been pre-read into the Nginx core request header buffer, the resulting cosocket object will take care of this to avoid potential data loss resulting from such pre-reading.
Chunked request bodies are not yet supported in this API.

Since the `v0.9.0` release, this function accepts an optional boolean `raw` argument. When this argument is `true`, this function returns a full-duplex cosocket object wrapping around the raw downstream connection socket, upon which you can call the [receive](#tcpsockreceive), [receiveany](#tcpsockreceiveany), [receiveuntil](#tcpsockreceiveuntil), and [send](#tcpsocksend) methods.

When the `raw` argument is `true`, it is required that no pending data from any previous [ngx.say](#ngxsay), [ngx.print](#ngxprint), or [ngx.send_headers](#ngxsend_headers) calls exists. So if you have these downstream output calls previously, you should call [ngx.flush(true)](#ngxflush) before calling `ngx.req.socket(true)` to ensure that there is no pending output data. If the request body has not been read yet, then this "raw socket" can also be used to read the request body.

You can use the "raw request socket" returned by `ngx.req.socket(true)` to implement fancy protocols like [WebSocket](https://en.wikipedia.org/wiki/WebSocket), or just emit your own raw HTTP response header or body data. You can refer to the [lua-resty-websocket library](https://github.com/openresty/lua-resty-websocket) for a real world example.

This function was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

ngx.exec
--------

**syntax:** *ngx.exec(uri, args?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Does an internal redirect to `uri` with `args` and is similar to the [echo_exec](http://github.com/openresty/echo-nginx-module#echo_exec) directive of the [echo-nginx-module](http://github.com/openresty/echo-nginx-module).

```lua

 ngx.exec('/some-location')
 ngx.exec('/some-location', 'a=3&b=5&c=6')
 ngx.exec('/some-location?a=3&b=5', 'c=6')
```

The optional second `args` can be used to specify extra URI query arguments, for example:

```lua

 ngx.exec("/foo", "a=3&b=hello%20world")
```

Alternatively, a Lua table can be passed for the `args` argument for ngx_lua to carry out URI escaping and string concatenation.

```lua

 ngx.exec("/foo", { a = 3, b = "hello world" })
```

The result is exactly the same as the previous example.

The format for the Lua table passed as the `args` argument is identical to the format used in the [ngx.encode_args](#ngxencode_args) method.

Named locations are also supported but the second `args` argument will be ignored if present and the querystring for the new target is inherited from the referring location (if any).

`GET /foo/file.php?a=hello` will return "hello" and not "goodbye" in the example below

```nginx

 location /foo {
     content_by_lua_block {
         ngx.exec("@bar", "a=goodbye")
     }
 }

 location @bar {
     content_by_lua_block {
         local args = ngx.req.get_uri_args()
         for key, val in pairs(args) do
             if key == "a" then
                 ngx.say(val)
             end
         end
     }
 }
```

Note that the `ngx.exec` method is different from [ngx.redirect](#ngxredirect) in that
it is purely an internal redirect and that no new external HTTP traffic is involved.

Also note that this method call terminates the processing of the current request and that it *must* be called before [ngx.send_headers](#ngxsend_headers) or explicit response body
outputs by either [ngx.print](#ngxprint) or [ngx.say](#ngxsay).

It is recommended that a coding style that combines this method call with the `return` statement, i.e., `return ngx.exec(...)` be adopted when this method call is used in contexts other than [header_filter_by_lua*](#header_filter_by_lua) to reinforce the fact that the request processing is being terminated.

[Back to TOC](#nginx-api-for-lua)

ngx.redirect
------------

**syntax:** *ngx.redirect(uri, status?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Issue an `HTTP 301` or `302` redirection to `uri`.

Note: this function throws a Lua error if the `uri` argument
contains unsafe characters (control characters).

The optional `status` parameter specifies the HTTP status code to be used. The following status codes are supported right now:

* `301`
* `302` (default)
* `303`
* `307`
* `308`

It is `302` (`ngx.HTTP_MOVED_TEMPORARILY`) by default.

Here is an example assuming the current server name is `localhost` and that it is listening on port 1984:

```lua

 return ngx.redirect("/foo")
```

which is equivalent to

```lua

 return ngx.redirect("/foo", ngx.HTTP_MOVED_TEMPORARILY)
```

Redirecting arbitrary external URLs is also supported, for example:

```lua

 return ngx.redirect("http://www.google.com")
```

We can also use the numerical code directly as the second `status` argument:

```lua

 return ngx.redirect("/foo", 301)
```

This method is similar to the [rewrite](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite) directive with the `redirect` modifier in the standard
[ngx_http_rewrite_module](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html), for example, this `nginx.conf` snippet

```nginx

 rewrite ^ /foo? redirect;  # nginx config
```

is equivalent to the following Lua code

```lua

 return ngx.redirect('/foo')  -- Lua code
```

while

```nginx

 rewrite ^ /foo? permanent;  # nginx config
```

is equivalent to

```lua

 return ngx.redirect('/foo', ngx.HTTP_MOVED_PERMANENTLY)  -- Lua code
```

URI arguments can be specified as well, for example:

```lua

 return ngx.redirect('/foo?a=3&b=4')
```

Note that this method call terminates the processing of the current request and that it *must* be called before [ngx.send_headers](#ngxsend_headers) or explicit response body
outputs by either [ngx.print](#ngxprint) or [ngx.say](#ngxsay).

It is recommended that a coding style that combines this method call with the `return` statement, i.e., `return ngx.redirect(...)` be adopted when this method call is used in contexts other than [header_filter_by_lua*](#header_filter_by_lua) to reinforce the fact that the request processing is being terminated.

[Back to TOC](#nginx-api-for-lua)

ngx.send_headers
----------------

**syntax:** *ok, err = ngx.send_headers()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Explicitly send out the response headers.

Since `v0.8.3` this function returns `1` on success, or returns `nil` and a string describing the error otherwise.

Note that there is normally no need to manually send out response headers as ngx_lua will automatically send headers out
before content is output with [ngx.say](#ngxsay) or [ngx.print](#ngxprint) or when [content_by_lua*](#content_by_lua) exits normally.

[Back to TOC](#nginx-api-for-lua)

ngx.headers_sent
----------------

**syntax:** *value = ngx.headers_sent*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Returns `true` if the response headers have been sent (by ngx_lua), and `false` otherwise.

This API was first introduced in ngx_lua v0.3.1rc6.

[Back to TOC](#nginx-api-for-lua)

ngx.print
---------

**syntax:** *ok, err = ngx.print(...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Emits arguments concatenated to the HTTP client (as response body). If response headers have not been sent, this function will send headers out first and then output body data.

Since `v0.8.3` this function returns `1` on success, or returns `nil` and a string describing the error otherwise.

Lua `nil` values will output `"nil"` strings and Lua boolean values will output `"true"` and `"false"` literal strings respectively.

Nested arrays of strings are permitted and the elements in the arrays will be sent one by one:

```lua

 local table = {
     "hello, ",
     {"world: ", true, " or ", false,
         {": ", nil}}
 }
 ngx.print(table)
```

will yield the output

```bash

 hello, world: true or false: nil
```

Non-array table arguments will cause a Lua exception to be thrown.

The `ngx.null` constant will yield the `"null"` string output.

This is an asynchronous call and will return immediately without waiting for all the data to be written into the system send buffer. To run in synchronous mode, call `ngx.flush(true)` after calling `ngx.print`. This can be particularly useful for streaming output. See [ngx.flush](#ngxflush) for more details.

Please note that both `ngx.print` and [ngx.say](#ngxsay) will always invoke the whole Nginx output body filter chain, which is an expensive operation. So be careful when calling either of these two in a tight loop; buffer the data yourself in Lua and save the calls.

[Back to TOC](#nginx-api-for-lua)

ngx.say
-------

**syntax:** *ok, err = ngx.say(...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Just as [ngx.print](#ngxprint) but also emit a trailing newline.

[Back to TOC](#nginx-api-for-lua)

ngx.log
-------

**syntax:** *ngx.log(log_level, ...)*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Log arguments concatenated to error.log with the given logging level.

Lua `nil` arguments are accepted and result in literal `"nil"` string while Lua booleans result in literal `"true"` or `"false"` string outputs. And the `ngx.null` constant will yield the `"null"` string output.

The `log_level` argument can take constants like `ngx.ERR` and `ngx.WARN`. Check out [Nginx log level constants](#nginx-log-level-constants) for details.

There is a hard coded `2048` byte limitation on error message lengths in the Nginx core. This limit includes trailing newlines and leading time stamps. If the message size exceeds this limit, Nginx will truncate the message text accordingly. This limit can be manually modified by editing the `NGX_MAX_ERROR_STR` macro definition in the `src/core/ngx_log.h` file in the Nginx source tree.

[Back to TOC](#nginx-api-for-lua)

ngx.flush
---------

**syntax:** *ok, err = ngx.flush(wait?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Flushes response output to the client.

`ngx.flush` accepts an optional boolean `wait` argument (Default: `false`) first introduced in the `v0.3.1rc34` release. When called with the default argument, it issues an asynchronous call (Returns immediately without waiting for output data to be written into the system send buffer). Calling the function with the `wait` argument set to `true` switches to synchronous mode.

In synchronous mode, the function will not return until all output data has been written into the system send buffer or until the [send_timeout](http://nginx.org/en/docs/http/ngx_http_core_module.html#send_timeout) setting has expired. Note that using the Lua coroutine mechanism means that this function does not block the Nginx event loop even in the synchronous mode.

When `ngx.flush(true)` is called immediately after [ngx.print](#ngxprint) or [ngx.say](#ngxsay), it causes the latter functions to run in synchronous mode. This can be particularly useful for streaming output.

Note that `ngx.flush` is not functional when in the HTTP 1.0 output buffering mode. See [HTTP 1.0 support](#http-10-support).

Since `v0.8.3` this function returns `1` on success, or returns `nil` and a string describing the error otherwise.

[Back to TOC](#nginx-api-for-lua)

ngx.exit
--------

**syntax:** *ngx.exit(status)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

When `status >= 200` (i.e., `ngx.HTTP_OK` and above), it will interrupt the execution of the current request and return status code to Nginx.

When `status == 0` (i.e., `ngx.OK`), it will only quit the current phase handler (or the content handler if the [content_by_lua*](#content_by_lua) directive is used) and continue to run later phases (if any) for the current request.

The `status` argument can be `ngx.OK`, `ngx.ERROR`, `ngx.HTTP_NOT_FOUND`,
`ngx.HTTP_MOVED_TEMPORARILY`, or other [HTTP status constants](#http-status-constants).

To return an error page with custom contents, use code snippets like this:

```lua

 ngx.status = ngx.HTTP_GONE
 ngx.say("This is our own content")
 -- to cause quit the whole request rather than the current phase handler
 ngx.exit(ngx.HTTP_OK)
```

The effect in action:

```bash

 $ curl -i http://localhost/test
 HTTP/1.1 410 Gone
 Server: nginx/1.0.6
 Date: Thu, 15 Sep 2011 00:51:48 GMT
 Content-Type: text/plain
 Transfer-Encoding: chunked
 Connection: keep-alive

 This is our own content
```

Number literals can be used directly as the argument, for instance,

```lua

 ngx.exit(501)
```

Note that while this method accepts all [HTTP status constants](#http-status-constants) as input, it only accepts `ngx.OK` and `ngx.ERROR` of the [core constants](#core-constants).

Also note that this method call terminates the processing of the current request and that it is recommended that a coding style that combines this method call with the `return` statement, i.e., `return ngx.exit(...)` be used to reinforce the fact that the request processing is being terminated.

When being used in the contexts of [header_filter_by_lua*](#header_filter_by_lua), [balancer_by_lua*](#balancer_by_lua_block), and
[ssl_session_store_by_lua*](#ssl_session_store_by_lua_block), `ngx.exit()` is
an asynchronous operation and will return immediately. This behavior may change in future and it is recommended that users always use `return` in combination as suggested above.

[Back to TOC](#nginx-api-for-lua)

ngx.eof
-------

**syntax:** *ok, err = ngx.eof()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Explicitly specify the end of the response output stream. In the case of HTTP 1.1 chunked encoded output, it will just trigger the Nginx core to send out the "last chunk".

When you disable the HTTP 1.1 keep-alive feature for your downstream connections, you can rely on well written HTTP clients to close the connection actively for you when you call this method. This trick can be used do back-ground jobs without letting the HTTP clients to wait on the connection, as in the following example:

```nginx

 location = /async {
     keepalive_timeout 0;
     content_by_lua_block {
         ngx.say("got the task!")
         ngx.eof()  -- well written HTTP clients will close the connection at this point
         -- access MySQL, PostgreSQL, Redis, Memcached, and etc here...
     }
 }
```

But if you create subrequests to access other locations configured by Nginx upstream modules, then you should configure those upstream modules to ignore client connection abortions if they are not by default. For example, by default the standard [ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html) will terminate both the subrequest and the main request as soon as the client closes the connection, so it is important to turn on the [proxy_ignore_client_abort](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ignore_client_abort) directive in your location block configured by [ngx_http_proxy_module](http://nginx.org/en/docs/http/ngx_http_proxy_module.html):

```nginx

 proxy_ignore_client_abort on;
```

A better way to do background jobs is to use the [ngx.timer.at](#ngxtimerat) API.

Since `v0.8.3` this function returns `1` on success, or returns `nil` and a string describing the error otherwise.

[Back to TOC](#nginx-api-for-lua)

ngx.sleep
---------

**syntax:** *ngx.sleep(seconds)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Sleeps for the specified seconds without blocking. One can specify time resolution up to 0.001 seconds (i.e., one millisecond).

Behind the scene, this method makes use of the Nginx timers.

Since the `0.7.20` release, The `0` time argument can also be specified.

This method was introduced in the `0.5.0rc30` release.

[Back to TOC](#nginx-api-for-lua)

ngx.escape_uri
--------------

**syntax:** *newstr = ngx.escape_uri(str, type?)*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Since `v0.10.16`, this function accepts an optional `type` argument.
It accepts the following values (defaults to `2`):

* `0`: escapes `str` as a full URI. And the characters
` ` (space), `#`, `%`,
`?`, 0x00 ~ 0x1F, 0x7F ~ 0xFF will be escaped.
* `2`: escape `str` as a URI component. All characters except
alphabetic characters, digits, `-`, `.`, `_`,
`~` will be encoded as `%XX`.

[Back to TOC](#nginx-api-for-lua)

ngx.unescape_uri
----------------

**syntax:** *newstr = ngx.unescape_uri(str)*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Unescape `str` as an escaped URI component.

For example,

```lua

 ngx.say(ngx.unescape_uri("b%20r56+7"))
```

gives the output


    b r56 7


Invalid escaping sequences are handled in a conventional way: `%`s are left unchanged. Also, characters that should not appear in escaped string are simply left unchanged.

For example,

```lua

 ngx.say(ngx.unescape_uri("try %search%%20%again%"))
```

gives the output


    try %search% %again%


(Note that `%20` following `%` got unescaped, even it can be considered a part of invalid sequence.)

[Back to TOC](#nginx-api-for-lua)

ngx.encode_args
---------------

**syntax:** *str = ngx.encode_args(table)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Encode the Lua table to a query args string according to the URI encoded rules.

For example,

```lua

 ngx.encode_args({foo = 3, ["b r"] = "hello world"})
```

yields


    foo=3&b%20r=hello%20world


The table keys must be Lua strings.

Multi-value query args are also supported. Just use a Lua table for the argument's value, for example:

```lua

 ngx.encode_args({baz = {32, "hello"}})
```

gives


    baz=32&baz=hello


If the value table is empty and the effect is equivalent to the `nil` value.

Boolean argument values are also supported, for instance,

```lua

 ngx.encode_args({a = true, b = 1})
```

yields


    a&b=1


If the argument value is `false`, then the effect is equivalent to the `nil` value.

This method was first introduced in the `v0.3.1rc27` release.

[Back to TOC](#nginx-api-for-lua)

ngx.decode_args
---------------

**syntax:** *table, err = ngx.decode_args(str, max_args?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Decodes a URI encoded query-string into a Lua table. This is the inverse function of [ngx.encode_args](#ngxencode_args).

The optional `max_args` argument can be used to specify the maximum number of arguments parsed from the `str` argument. By default, a maximum of 100 request arguments are parsed (including those with the same name) and that additional URI arguments are silently discarded to guard against potential denial of service attacks. Since `v0.10.13`, when the limit is exceeded, it will return a second value which is the string `"truncated"`.

This argument can be set to zero to remove the limit and to process all request arguments received:

```lua

 local args = ngx.decode_args(str, 0)
```

Removing the `max_args` cap is strongly discouraged.

This method was introduced in the `v0.5.0rc29`.

[Back to TOC](#nginx-api-for-lua)

ngx.encode_base64
-----------------

**syntax:** *newstr = ngx.encode_base64(str, no_padding?)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Encodes `str` to a base64 digest.

Since the `0.9.16` release, an optional boolean-typed `no_padding` argument can be specified to control whether the base64 padding should be appended to the resulting digest (default to `false`, i.e., with padding enabled).

[Back to TOC](#nginx-api-for-lua)

ngx.decode_base64
-----------------

**syntax:** *newstr = ngx.decode_base64(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Decodes the `str` argument as a base64 digest to the raw form. Returns `nil` if `str` is not well formed.

[Back to TOC](#nginx-api-for-lua)

ngx.crc32_short
---------------

**syntax:** *intval = ngx.crc32_short(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Calculates the CRC-32 (Cyclic Redundancy Code) digest for the `str` argument.

This method performs better on relatively short `str` inputs (i.e., less than 30 ~ 60 bytes), as compared to [ngx.crc32_long](#ngxcrc32_long). The result is exactly the same as [ngx.crc32_long](#ngxcrc32_long).

Behind the scene, it is just a thin wrapper around the `ngx_crc32_short` function defined in the Nginx core.

This API was first introduced in the `v0.3.1rc8` release.

[Back to TOC](#nginx-api-for-lua)

ngx.crc32_long
--------------

**syntax:** *intval = ngx.crc32_long(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Calculates the CRC-32 (Cyclic Redundancy Code) digest for the `str` argument.

This method performs better on relatively long `str` inputs (i.e., longer than 30 ~ 60 bytes), as compared to [ngx.crc32_short](#ngxcrc32_short).  The result is exactly the same as [ngx.crc32_short](#ngxcrc32_short).

Behind the scene, it is just a thin wrapper around the `ngx_crc32_long` function defined in the Nginx core.

This API was first introduced in the `v0.3.1rc8` release.

[Back to TOC](#nginx-api-for-lua)

ngx.hmac_sha1
-------------

**syntax:** *digest = ngx.hmac_sha1(secret_key, str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Computes the [HMAC-SHA1](https://en.wikipedia.org/wiki/HMAC) digest of the argument `str` and turns the result using the secret key `<secret_key>`.

The raw binary form of the `HMAC-SHA1` digest will be generated, use [ngx.encode_base64](#ngxencode_base64), for example, to encode the result to a textual representation if desired.

For example,

```lua

 local key = "thisisverysecretstuff"
 local src = "some string we want to sign"
 local digest = ngx.hmac_sha1(key, src)
 ngx.say(ngx.encode_base64(digest))
```

yields the output


    R/pvxzHC4NLtj7S+kXFg/NePTmk=


This API requires the OpenSSL library enabled in the Nginx build (usually by passing the `--with-http_ssl_module` option to the `./configure` script).

This function was first introduced in the `v0.3.1rc29` release.

[Back to TOC](#nginx-api-for-lua)

ngx.md5
-------

**syntax:** *digest = ngx.md5(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the hexadecimal representation of the MD5 digest of the `str` argument.

For example,

```nginx

 location = /md5 {
     content_by_lua_block {
         ngx.say(ngx.md5("hello"))
     }
 }
```

yields the output


    5d41402abc4b2a76b9719d911017c592


See [ngx.md5_bin](#ngxmd5_bin) if the raw binary MD5 digest is required.

[Back to TOC](#nginx-api-for-lua)

ngx.md5_bin
-----------

**syntax:** *digest = ngx.md5_bin(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the binary form of the MD5 digest of the `str` argument.

See [ngx.md5](#ngxmd5) if the hexadecimal form of the MD5 digest is required.

[Back to TOC](#nginx-api-for-lua)

ngx.sha1_bin
------------

**syntax:** *digest = ngx.sha1_bin(str)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the binary form of the SHA-1 digest of the `str` argument.

This function requires SHA-1 support in the Nginx build. (This usually just means OpenSSL should be installed while building Nginx).

This function was first introduced in the `v0.5.0rc6`.

[Back to TOC](#nginx-api-for-lua)

ngx.quote_sql_str
-----------------

**syntax:** *quoted_value = ngx.quote_sql_str(raw_value)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns a quoted SQL string literal according to the MySQL quoting rules.

[Back to TOC](#nginx-api-for-lua)

ngx.today
---------

**syntax:** *str = ngx.today()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns current date (in the format `yyyy-mm-dd`) from the Nginx cached time (no syscall involved unlike Lua's date library).

This is the local time.

[Back to TOC](#nginx-api-for-lua)

ngx.time
--------

**syntax:** *secs = ngx.time()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the elapsed seconds from the epoch for the current time stamp from the Nginx cached time (no syscall involved unlike Lua's date library).

Updates of the Nginx time cache can be forced by calling [ngx.update_time](#ngxupdate_time) first.

[Back to TOC](#nginx-api-for-lua)

ngx.now
-------

**syntax:** *secs = ngx.now()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns a floating-point number for the elapsed time in seconds (including milliseconds as the decimal part) from the epoch for the current time stamp from the Nginx cached time (no syscall involved unlike Lua's date library).

You can forcibly update the Nginx time cache by calling [ngx.update_time](#ngxupdate_time) first.

This API was first introduced in `v0.3.1rc32`.

[Back to TOC](#nginx-api-for-lua)

ngx.update_time
---------------

**syntax:** *ngx.update_time()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Forcibly updates the Nginx current time cache. This call involves a syscall and thus has some overhead, so do not abuse it.

This API was first introduced in `v0.3.1rc32`.

[Back to TOC](#nginx-api-for-lua)

ngx.localtime
-------------

**syntax:** *str = ngx.localtime()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the current time stamp (in the format `yyyy-mm-dd hh:mm:ss`) of the Nginx cached time (no syscall involved unlike Lua's [os.date](https://www.lua.org/manual/5.1/manual.html#pdf-os.date) function).

This is the local time.

[Back to TOC](#nginx-api-for-lua)

ngx.utctime
-----------

**syntax:** *str = ngx.utctime()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the current time stamp (in the format `yyyy-mm-dd hh:mm:ss`) of the Nginx cached time (no syscall involved unlike Lua's [os.date](https://www.lua.org/manual/5.1/manual.html#pdf-os.date) function).

This is the UTC time.

[Back to TOC](#nginx-api-for-lua)

ngx.cookie_time
---------------

**syntax:** *str = ngx.cookie_time(sec)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns a formatted string can be used as the cookie expiration time. The parameter `sec` is the time stamp in seconds (like those returned from [ngx.time](#ngxtime)).

```nginx

 ngx.say(ngx.cookie_time(1290079655))
     -- yields "Thu, 18-Nov-10 11:27:35 GMT"
```

[Back to TOC](#nginx-api-for-lua)

ngx.http_time
-------------

**syntax:** *str = ngx.http_time(sec)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns a formated string can be used as the http header time (for example, being used in `Last-Modified` header). The parameter `sec` is the time stamp in seconds (like those returned from [ngx.time](#ngxtime)).

```nginx

 ngx.say(ngx.http_time(1290079655))
     -- yields "Thu, 18 Nov 2010 11:27:35 GMT"
```

[Back to TOC](#nginx-api-for-lua)

ngx.parse_http_time
-------------------

**syntax:** *sec = ngx.parse_http_time(str)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Parse the http time string (as returned by [ngx.http_time](#ngxhttp_time)) into seconds. Returns the seconds or `nil` if the input string is in bad forms.

```nginx

 local time = ngx.parse_http_time("Thu, 18 Nov 2010 11:27:35 GMT")
 if time == nil then
     ...
 end
```

[Back to TOC](#nginx-api-for-lua)

ngx.is_subrequest
-----------------

**syntax:** *value = ngx.is_subrequest*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;*

Returns `true` if the current request is an Nginx subrequest, or `false` otherwise.

[Back to TOC](#nginx-api-for-lua)

ngx.re.match
------------

**syntax:** *captures, err = ngx.re.match(subject, regex, options?, ctx?, res_table?)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Matches the `subject` string using the Perl compatible regular expression `regex` with the optional `options`.

Only the first occurrence of the match is returned, or `nil` if no match is found. In case of errors, like seeing a bad regular expression or exceeding the PCRE stack limit, `nil` and a string describing the error will be returned.

When a match is found, a Lua table `captures` is returned, where `captures[0]` holds the whole substring being matched, and `captures[1]` holds the first parenthesized sub-pattern's capturing, `captures[2]` the second, and so on.

```lua

 local m, err = ngx.re.match("hello, 1234", "[0-9]+")
 if m then
     -- m[0] == "1234"

 else
     if err then
         ngx.log(ngx.ERR, "error: ", err)
         return
     end

     ngx.say("match not found")
 end
```

```lua

 local m, err = ngx.re.match("hello, 1234", "([0-9])[0-9]+")
 -- m[0] == "1234"
 -- m[1] == "1"
```

Named captures are also supported since the `v0.7.14` release
and are returned in the same Lua table as key-value pairs as the numbered captures.

```lua

 local m, err = ngx.re.match("hello, 1234", "([0-9])(?<remaining>[0-9]+)")
 -- m[0] == "1234"
 -- m[1] == "1"
 -- m[2] == "234"
 -- m["remaining"] == "234"
```

Unmatched subpatterns will have `false` values in their `captures` table fields.

```lua

 local m, err = ngx.re.match("hello, world", "(world)|(hello)|(?<named>howdy)")
 -- m[0] == "hello"
 -- m[1] == false
 -- m[2] == "hello"
 -- m[3] == false
 -- m["named"] == false
```

Specify `options` to control how the match operation will be performed. The following option characters are supported:


    a             anchored mode (only match from the beginning)

    d             enable the DFA mode (or the longest token match semantics).
                  this requires PCRE 6.0+ or else a Lua exception will be thrown.
                  first introduced in ngx_lua v0.3.1rc30.

    D             enable duplicate named pattern support. This allows named
                  subpattern names to be repeated, returning the captures in
                  an array-like Lua table. for example,
                    local m = ngx.re.match("hello, world",
                                           "(?<named>\w+), (?<named>\w+)",
                                           "D")
                    -- m["named"] == {"hello", "world"}
                  this option was first introduced in the v0.7.14 release.
                  this option requires at least PCRE 8.12.

    i             case insensitive mode (similar to Perl's /i modifier)

    j             enable PCRE JIT compilation, this requires PCRE 8.21+ which
                  must be built with the --enable-jit option. for optimum performance,
                  this option should always be used together with the 'o' option.
                  first introduced in ngx_lua v0.3.1rc30.

    J             enable the PCRE Javascript compatible mode. this option was
                  first introduced in the v0.7.14 release. this option requires
                  at least PCRE 8.12.

    m             multi-line mode (similar to Perl's /m modifier)

    o             compile-once mode (similar to Perl's /o modifier),
                  to enable the worker-process-level compiled-regex cache

    s             single-line mode (similar to Perl's /s modifier)

    u             UTF-8 mode. this requires PCRE to be built with
                  the --enable-utf8 option or else a Lua exception will be thrown.

    U             similar to "u" but disables PCRE's UTF-8 validity check on
                  the subject string. first introduced in ngx_lua v0.8.1.

    x             extended mode (similar to Perl's /x modifier)


These options can be combined:

```nginx

 local m, err = ngx.re.match("hello, world", "HEL LO", "ix")
 -- m[0] == "hello"
```

```nginx

 local m, err = ngx.re.match("hello, 美好生活", "HELLO, (.{2})", "iu")
 -- m[0] == "hello, 美好"
 -- m[1] == "美好"
```

The `o` option is useful for performance tuning, because the regex pattern in question will only be compiled once, cached in the worker-process level, and shared among all requests in the current Nginx worker process. The upper limit of the regex cache can be tuned via the [lua_regex_cache_max_entries](#lua_regex_cache_max_entries) directive.

The optional fourth argument, `ctx`, can be a Lua table holding an optional `pos` field. When the `pos` field in the `ctx` table argument is specified, `ngx.re.match` will start matching from that offset (starting from 1). Regardless of the presence of the `pos` field in the `ctx` table, `ngx.re.match` will always set this `pos` field to the position *after* the substring matched by the whole pattern in case of a successful match. When match fails, the `ctx` table will be left intact.

```lua

 local ctx = {}
 local m, err = ngx.re.match("1234, hello", "[0-9]+", "", ctx)
      -- m[0] = "1234"
      -- ctx.pos == 5
```

```lua

 local ctx = { pos = 2 }
 local m, err = ngx.re.match("1234, hello", "[0-9]+", "", ctx)
      -- m[0] = "234"
      -- ctx.pos == 5
```

The `ctx` table argument combined with the `a` regex modifier can be used to construct a lexer atop `ngx.re.match`.

Note that, the `options` argument is not optional when the `ctx` argument is specified and that the empty Lua string (`""`) must be used as placeholder for `options` if no meaningful regex options are required.

This method requires the PCRE library enabled in Nginx ([Known Issue With Special Escaping Sequences](#special-escaping-sequences)).

To confirm that PCRE JIT is enabled, activate the Nginx debug log by adding the `--with-debug` option to Nginx or OpenResty's `./configure` script. Then, enable the "debug" error log level in `error_log` directive. The following message will be generated if PCRE JIT is enabled:


    pcre JIT compiling result: 1


Starting from the `0.9.4` release, this function also accepts a 5th argument, `res_table`, for letting the caller supply the Lua table used to hold all the capturing results. Starting from `0.9.6`, it is the caller's responsibility to ensure this table is empty. This is very useful for recycling Lua tables and saving GC and table allocation overhead.

This feature was introduced in the `v0.2.1rc11` release.

[Back to TOC](#nginx-api-for-lua)

ngx.re.find
-----------

**syntax:** *from, to, err = ngx.re.find(subject, regex, options?, ctx?, nth?)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to [ngx.re.match](#ngxrematch) but only returns the beginning index (`from`) and end index (`to`) of the matched substring. The returned indexes are 1-based and can be fed directly into the [string.sub](https://www.lua.org/manual/5.1/manual.html#pdf-string.sub) API function to obtain the matched substring.

In case of errors (like bad regexes or any PCRE runtime errors), this API function returns two `nil` values followed by a string describing the error.

If no match is found, this function just returns a `nil` value.

Below is an example:

```lua

 local s = "hello, 1234"
 local from, to, err = ngx.re.find(s, "([0-9]+)", "jo")
 if from then
     ngx.say("from: ", from)
     ngx.say("to: ", to)
     ngx.say("matched: ", string.sub(s, from, to))
 else
     if err then
         ngx.say("error: ", err)
         return
     end
     ngx.say("not matched!")
 end
```

This example produces the output

    from: 8
    to: 11
    matched: 1234

Because this API function does not create new Lua strings nor new Lua tables, it is much faster than [ngx.re.match](#ngxrematch). It should be used wherever possible.

Since the `0.9.3` release, an optional 5th argument, `nth`, is supported to specify which (submatch) capture's indexes to return. When `nth` is 0 (which is the default), the indexes for the whole matched substring is returned; when `nth` is 1, then the 1st submatch capture's indexes are returned; when `nth` is 2, then the 2nd submatch capture is returned, and so on. When the specified submatch does not have a match, then two `nil` values will be returned. Below is an example for this:

```lua

 local str = "hello, 1234"
 local from, to = ngx.re.find(str, "([0-9])([0-9]+)", "jo", nil, 2)
 if from then
     ngx.say("matched 2nd submatch: ", string.sub(str, from, to))  -- yields "234"
 end
```

This API function was first introduced in the `v0.9.2` release.

[Back to TOC](#nginx-api-for-lua)

ngx.re.gmatch
-------------

**syntax:** *iterator, err = ngx.re.gmatch(subject, regex, options?)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to [ngx.re.match](#ngxrematch), but returns a Lua iterator instead, so as to let the user programmer iterate all the matches over the `<subject>` string argument with the PCRE `regex`.

In case of errors, like seeing an ill-formed regular expression, `nil` and a string describing the error will be returned.

Here is a small example to demonstrate its basic usage:

```lua

 local iterator, err = ngx.re.gmatch("hello, world!", "([a-z]+)", "i")
 if not iterator then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 local m
 m, err = iterator()    -- m[0] == m[1] == "hello"
 if err then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 m, err = iterator()    -- m[0] == m[1] == "world"
 if err then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 m, err = iterator()    -- m == nil
 if err then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end
```

More often we just put it into a Lua loop:

```lua

 local it, err = ngx.re.gmatch("hello, world!", "([a-z]+)", "i")
 if not it then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 while true do
     local m, err = it()
     if err then
         ngx.log(ngx.ERR, "error: ", err)
         return
     end

     if not m then
         -- no match found (any more)
         break
     end

     -- found a match
     ngx.say(m[0])
     ngx.say(m[1])
 end
```

The optional `options` argument takes exactly the same semantics as the [ngx.re.match](#ngxrematch) method.

The current implementation requires that the iterator returned should only be used in a single request. That is, one should *not* assign it to a variable belonging to persistent namespace like a Lua package.

This method requires the PCRE library enabled in Nginx ([Known Issue With Special Escaping Sequences](#special-escaping-sequences)).

This feature was first introduced in the `v0.2.1rc12` release.

[Back to TOC](#nginx-api-for-lua)

ngx.re.sub
----------

**syntax:** *newstr, n, err = ngx.re.sub(subject, regex, replace, options?)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Substitutes the first match of the Perl compatible regular expression `regex` on the `subject` argument string with the string or function argument `replace`. The optional `options` argument has exactly the same meaning as in [ngx.re.match](#ngxrematch).

This method returns the resulting new string as well as the number of successful substitutions. In case of failures, like syntax errors in the regular expressions or the `<replace>` string argument, it will return `nil` and a string describing the error.

When the `replace` is a string, then it is treated as a special template for string replacement. For example,

```lua

 local newstr, n, err = ngx.re.sub("hello, 1234", "([0-9])[0-9]", "[$0][$1]")
 if not newstr then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 -- newstr == "hello, [12][1]34"
 -- n == 1
```

where `$0` referring to the whole substring matched by the pattern and `$1` referring to the first parenthesized capturing substring.

Curly braces can also be used to disambiguate variable names from the background string literals:

```lua

 local newstr, n, err = ngx.re.sub("hello, 1234", "[0-9]", "${0}00")
 -- newstr == "hello, 100234"
 -- n == 1
```

Literal dollar sign characters (`$`) in the `replace` string argument can be escaped by another dollar sign, for instance,

```lua

 local newstr, n, err = ngx.re.sub("hello, 1234", "[0-9]", "$$")
 -- newstr == "hello, $234"
 -- n == 1
```

Do not use backlashes to escape dollar signs; it will not work as expected.

When the `replace` argument is of type "function", then it will be invoked with the "match table" as the argument to generate the replace string literal for substitution. The "match table" fed into the `replace` function is exactly the same as the return value of [ngx.re.match](#ngxrematch). Here is an example:

```lua

 local func = function (m)
     return "[" .. m[0] .. "][" .. m[1] .. "]"
 end

 local newstr, n, err = ngx.re.sub("hello, 1234", "( [0-9] ) [0-9]", func, "x")
 -- newstr == "hello, [12][1]34"
 -- n == 1
```

The dollar sign characters in the return value of the `replace` function argument are not special at all.

This method requires the PCRE library enabled in Nginx ([Known Issue With Special Escaping Sequences](#special-escaping-sequences)).

This feature was first introduced in the `v0.2.1rc13` release.

[Back to TOC](#nginx-api-for-lua)

ngx.re.gsub
-----------

**syntax:** *newstr, n, err = ngx.re.gsub(subject, regex, replace, options?)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Just like [ngx.re.sub](#ngxresub), but does global substitution.

Here is some examples:

```lua

 local newstr, n, err = ngx.re.gsub("hello, world", "([a-z])[a-z]+", "[$0,$1]", "i")
 if not newstr then
     ngx.log(ngx.ERR, "error: ", err)
     return
 end

 -- newstr == "[hello,h], [world,w]"
 -- n == 2
```

```lua

 local func = function (m)
     return "[" .. m[0] .. "," .. m[1] .. "]"
 end
 local newstr, n, err = ngx.re.gsub("hello, world", "([a-z])[a-z]+", func, "i")
 -- newstr == "[hello,h], [world,w]"
 -- n == 2
```

This method requires the PCRE library enabled in Nginx ([Known Issue With Special Escaping Sequences](#special-escaping-sequences)).

This feature was first introduced in the `v0.2.1rc15` release.

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT
---------------

**syntax:** *dict = ngx.shared.DICT*

**syntax:** *dict = ngx.shared\[name_var\]*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Fetching the shm-based Lua dictionary object for the shared memory zone named `DICT` defined by the [lua_shared_dict](#lua_shared_dict) directive.

Shared memory zones are always shared by all the Nginx worker processes in the current Nginx server instance.

The resulting object `dict` has the following methods:

* [get](#ngxshareddictget)
* [get_stale](#ngxshareddictget_stale)
* [set](#ngxshareddictset)
* [safe_set](#ngxshareddictsafe_set)
* [add](#ngxshareddictadd)
* [safe_add](#ngxshareddictsafe_add)
* [replace](#ngxshareddictreplace)
* [delete](#ngxshareddictdelete)
* [incr](#ngxshareddictincr)
* [lpush](#ngxshareddictlpush)
* [rpush](#ngxshareddictrpush)
* [lpop](#ngxshareddictlpop)
* [rpop](#ngxshareddictrpop)
* [llen](#ngxshareddictllen)
* [ttl](#ngxshareddictttl)
* [expire](#ngxshareddictexpire)
* [flush_all](#ngxshareddictflush_all)
* [flush_expired](#ngxshareddictflush_expired)
* [get_keys](#ngxshareddictget_keys)
* [capacity](#ngxshareddictcapacity)
* [free_space](#ngxshareddictfree_space)

All these methods are *atomic* operations, that is, safe from concurrent accesses from multiple Nginx worker processes for the same `lua_shared_dict` zone.

Here is an example:

```nginx

 http {
     lua_shared_dict dogs 10m;
     server {
         location /set {
             content_by_lua_block {
                 local dogs = ngx.shared.dogs
                 dogs:set("Jim", 8)
                 ngx.say("STORED")
             }
         }
         location /get {
             content_by_lua_block {
                 local dogs = ngx.shared.dogs
                 ngx.say(dogs:get("Jim"))
             }
         }
     }
 }
```

Let us test it:

```bash

 $ curl localhost/set
 STORED

 $ curl localhost/get
 8

 $ curl localhost/get
 8
```

The number `8` will be consistently output when accessing `/get` regardless of how many Nginx workers there are because the `dogs` dictionary resides in the shared memory and visible to *all* of the worker processes.

The shared dictionary will retain its contents through a server config reload (either by sending the `HUP` signal to the Nginx process or by using the `-s reload` command-line option).

The contents in the dictionary storage will be lost, however, when the Nginx server quits.

This feature was first introduced in the `v0.3.1rc22` release.

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.get
-------------------

**syntax:** *value, flags = ngx.shared.DICT:get(key)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Retrieving the value in the dictionary [ngx.shared.DICT](#ngxshareddict) for the key `key`. If the key does not exist or has expired, then `nil` will be returned.

In case of errors, `nil` and a string describing the error will be returned.

The value returned will have the original data type when they were inserted into the dictionary, for example, Lua booleans, numbers, or strings.

The first argument to this method must be the dictionary object itself, for example,

```lua

 local cats = ngx.shared.cats
 local value, flags = cats.get(cats, "Marry")
```

or use Lua's syntactic sugar for method calls:

```lua

 local cats = ngx.shared.cats
 local value, flags = cats:get("Marry")
```

These two forms are fundamentally equivalent.

If the user flags is `0` (the default), then no flags value will be returned.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.get_stale
-------------------------

**syntax:** *value, flags, stale = ngx.shared.DICT:get_stale(key)*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the [get](#ngxshareddictget) method but returns the value even if the key has already expired.

Returns a 3rd value, `stale`, indicating whether the key has expired or not.

Note that the value of an expired key is not guaranteed to be available so one should never rely on the availability of expired items.

This method was first introduced in the `0.8.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.set
-------------------

**syntax:** *success, err, forcible = ngx.shared.DICT:set(key, value, exptime?, flags?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Unconditionally sets a key-value pair into the shm-based dictionary [ngx.shared.DICT](#ngxshareddict). Returns three values:

* `success`: boolean value to indicate whether the key-value pair is stored or not.
* `err`: textual error message, can be `"no memory"`.
* `forcible`: a boolean value to indicate whether other valid items have been removed forcibly when out of storage in the shared memory zone.

The `value` argument inserted can be Lua booleans, numbers, strings, or `nil`. Their value type will also be stored into the dictionary and the same data type can be retrieved later via the [get](#ngxshareddictget) method.

The optional `exptime` argument specifies expiration time (in seconds) for the inserted key-value pair. The time resolution is `0.001` seconds. If the `exptime` takes the value `0` (which is the default), then the item will never expire.

The optional `flags` argument specifies a user flags value associated with the entry to be stored. It can also be retrieved later with the value. The user flags is stored as an unsigned 32-bit integer internally. Defaults to `0`. The user flags argument was first introduced in the `v0.5.0rc2` release.

When it fails to allocate memory for the current key-value item, then `set` will try removing existing items in the storage according to the Least-Recently Used (LRU) algorithm. Note that, LRU takes priority over expiration time here. If up to tens of existing items have been removed and the storage left is still insufficient (either due to the total capacity limit specified by [lua_shared_dict](#lua_shared_dict) or memory segmentation), then the `err` return value will be `no memory` and `success` will be `false`.

If the sizes of items in the dictionary are not multiples or even powers of a certain value (like 2), it is easier to encounter `no memory` error because of memory fragmentation. It is recommended to use different dictionaries for different sizes of items.

When you encounter `no memory` error, you can also evict more least-recently-used items by retrying this method call more times to to make room for the current item.

If this method succeeds in storing the current item by forcibly removing other not-yet-expired items in the dictionary via LRU, the `forcible` return value will be `true`. If it stores the item without forcibly removing other valid items, then the return value `forcible` will be `false`.

The first argument to this method must be the dictionary object itself, for example,

```lua

 local cats = ngx.shared.cats
 local succ, err, forcible = cats.set(cats, "Marry", "it is a nice cat!")
```

or use Lua's syntactic sugar for method calls:

```lua

 local cats = ngx.shared.cats
 local succ, err, forcible = cats:set("Marry", "it is a nice cat!")
```

These two forms are fundamentally equivalent.

This feature was first introduced in the `v0.3.1rc22` release.

Please note that while internally the key-value pair is set atomically, the atomicity does not go across the method call boundary.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.safe_set
------------------------

**syntax:** *ok, err = ngx.shared.DICT:safe_set(key, value, exptime?, flags?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the [set](#ngxshareddictset) method, but never overrides the (least recently used) unexpired items in the store when running out of storage in the shared memory zone. In this case, it will immediately return `nil` and the string "no memory".

This feature was first introduced in the `v0.7.18` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.add
-------------------

**syntax:** *success, err, forcible = ngx.shared.DICT:add(key, value, exptime?, flags?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Just like the [set](#ngxshareddictset) method, but only stores the key-value pair into the dictionary [ngx.shared.DICT](#ngxshareddict) if the key does *not* exist.

If the `key` argument already exists in the dictionary (and not expired for sure), the `success` return value will be `false` and the `err` return value will be `"exists"`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.safe_add
------------------------

**syntax:** *ok, err = ngx.shared.DICT:safe_add(key, value, exptime?, flags?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the [add](#ngxshareddictadd) method, but never overrides the (least recently used) unexpired items in the store when running out of storage in the shared memory zone. In this case, it will immediately return `nil` and the string "no memory".

This feature was first introduced in the `v0.7.18` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.replace
-----------------------

**syntax:** *success, err, forcible = ngx.shared.DICT:replace(key, value, exptime?, flags?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Just like the [set](#ngxshareddictset) method, but only stores the key-value pair into the dictionary [ngx.shared.DICT](#ngxshareddict) if the key *does* exist.

If the `key` argument does *not* exist in the dictionary (or expired already), the `success` return value will be `false` and the `err` return value will be `"not found"`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.delete
----------------------

**syntax:** *ngx.shared.DICT:delete(key)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Unconditionally removes the key-value pair from the shm-based dictionary [ngx.shared.DICT](#ngxshareddict).

It is equivalent to `ngx.shared.DICT:set(key, nil)`.

This feature was first introduced in the `v0.3.1rc22` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.incr
--------------------

**syntax:** *newval, err, forcible? = ngx.shared.DICT:incr(key, value, init?, init_ttl?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

**optional requirement:** `resty.core.shdict` or `resty.core`

Increments the (numerical) value for `key` in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict) by the step value `value`. Returns the new resulting number if the operation is successfully completed or `nil` and an error message otherwise.

When the key does not exist or has already expired in the shared dictionary,

1. if the `init` argument is not specified or takes the value `nil`, this method will return `nil` and the error string `"not found"`, or
1. if the `init` argument takes a number value, this method will create a new `key` with the value `init + value`.

Like the [add](#ngxshareddictadd) method, it also overrides the (least recently used) unexpired items in the store when running out of storage in the shared memory zone.

The optional `init_ttl` argument specifies expiration time (in seconds) of the value when it is initialized via the `init` argument. The time resolution is `0.001` seconds. If `init_ttl` takes the value `0` (which is the default), then the item will never expire. This argument cannot be provided without providing the `init` argument as well, and has no effect if the value already exists (e.g., if it was previously inserted via [set](#ngxshareddictset) or the likes).

**Note:** Usage of the `init_ttl` argument requires the `resty.core.shdict` or `resty.core` modules from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library. Example:

```lua

 require "resty.core"

 local cats = ngx.shared.cats
 local newval, err = cats:incr("black_cats", 1, 0, 0.1)

 print(newval) -- 1

 ngx.sleep(0.2)

 local val, err = cats:get("black_cats")
 print(val) -- nil
```

The `forcible` return value will always be `nil` when the `init` argument is not specified.

If this method succeeds in storing the current item by forcibly removing other not-yet-expired items in the dictionary via LRU, the `forcible` return value will be `true`. If it stores the item without forcibly removing other valid items, then the return value `forcible` will be `false`.

If the original value is not a valid Lua number in the dictionary, it will return `nil` and `"not a number"`.

The `value` argument and `init` argument can be any valid Lua numbers, like negative numbers or floating-point numbers.

This method was first introduced in the `v0.3.1rc22` release.

The optional `init` parameter was first added in the `v0.10.6` release.

The optional `init_ttl` parameter was introduced in the `v0.10.12rc2` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.lpush
---------------------

**syntax:** *length, err = ngx.shared.DICT:lpush(key, value)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Inserts the specified (numerical or string) `value` at the head of the list named `key` in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict). Returns the number of elements in the list after the push operation.

If `key` does not exist, it is created as an empty list before performing the push operation. When the `key` already takes a value that is not a list, it will return `nil` and `"value not a list"`.

It never overrides the (least recently used) unexpired items in the store when running out of storage in the shared memory zone. In this case, it will immediately return `nil` and the string "no memory".

This feature was first introduced in the `v0.10.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.rpush
---------------------

**syntax:** *length, err = ngx.shared.DICT:rpush(key, value)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the [lpush](#ngxshareddictlpush) method, but inserts the specified (numerical or string) `value` at the tail of the list named `key`.

This feature was first introduced in the `v0.10.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.lpop
--------------------

**syntax:** *val, err = ngx.shared.DICT:lpop(key)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Removes and returns the first element of the list named `key` in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict).

If `key` does not exist, it will return `nil`. When the `key` already takes a value that is not a list, it will return `nil` and `"value not a list"`.

This feature was first introduced in the `v0.10.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.rpop
--------------------

**syntax:** *val, err = ngx.shared.DICT:rpop(key)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Removes and returns the last element of the list named `key` in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict).

If `key` does not exist, it will return `nil`. When the `key` already takes a value that is not a list, it will return `nil` and `"value not a list"`.

This feature was first introduced in the `v0.10.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.llen
--------------------

**syntax:** *len, err = ngx.shared.DICT:llen(key)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the number of elements in the list named `key` in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict).

If key does not exist, it is interpreted as an empty list and 0 is returned. When the `key` already takes a value that is not a list, it will return `nil` and `"value not a list"`.

This feature was first introduced in the `v0.10.6` release.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.ttl
-------------------

**syntax:** *ttl, err = ngx.shared.DICT:ttl(key)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

**requires:** `resty.core.shdict` or `resty.core`

Retrieves the remaining TTL (time-to-live in seconds) of a key-value pair in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict). Returns the TTL as a number if the operation is successfully completed or `nil` and an error message otherwise.

If the key does not exist (or has already expired), this method will return `nil` and the error string `"not found"`.

The TTL is originally determined by the `exptime` argument of the [set](#ngxshareddictset), [add](#ngxshareddictadd), [replace](#ngxshareddictreplace) (and the likes) methods. It has a time resolution of `0.001` seconds. A value of `0` means that the item will never expire.

Example:

```lua

 require "resty.core"

 local cats = ngx.shared.cats
 local succ, err = cats:set("Marry", "a nice cat", 0.5)

 ngx.sleep(0.2)

 local ttl, err = cats:ttl("Marry")
 ngx.say(ttl) -- 0.3
```

This feature was first introduced in the `v0.10.11` release.

**Note:** This method requires the `resty.core.shdict` or `resty.core` modules from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.expire
----------------------

**syntax:** *success, err = ngx.shared.DICT:expire(key, exptime)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

**requires:** `resty.core.shdict` or `resty.core`

Updates the `exptime` (in second) of a key-value pair in the shm-based dictionary [ngx.shared.DICT](#ngxshareddict). Returns a boolean indicating success if the operation completes or `nil` and an error message otherwise.

If the key does not exist, this method will return `nil` and the error string `"not found"`.

The `exptime` argument has a resolution of `0.001` seconds. If `exptime` is `0`, then the item will never expire.

Example:

```lua

 require "resty.core"

 local cats = ngx.shared.cats
 local succ, err = cats:set("Marry", "a nice cat", 0.1)

 succ, err = cats:expire("Marry", 0.5)

 ngx.sleep(0.2)

 local val, err = cats:get("Marry")
 ngx.say(val) -- "a nice cat"
```

This feature was first introduced in the `v0.10.11` release.

**Note:** This method requires the `resty.core.shdict` or `resty.core` modules from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.flush_all
-------------------------

**syntax:** *ngx.shared.DICT:flush_all()*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Flushes out all the items in the dictionary. This method does not actually free up all the memory blocks in the dictionary but just marks all the existing items as expired.

This feature was first introduced in the `v0.5.0rc17` release.

See also [ngx.shared.DICT.flush_expired](#ngxshareddictflush_expired) and [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.flush_expired
-----------------------------

**syntax:** *flushed = ngx.shared.DICT:flush_expired(max_count?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Flushes out the expired items in the dictionary, up to the maximal number specified by the optional `max_count` argument. When the `max_count` argument is given `0` or not given at all, then it means unlimited. Returns the number of items that have actually been flushed.

Unlike the [flush_all](#ngxshareddictflush_all) method, this method actually frees up the memory used by the expired items.

This feature was first introduced in the `v0.6.3` release.

See also [ngx.shared.DICT.flush_all](#ngxshareddictflush_all) and [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.get_keys
------------------------

**syntax:** *keys = ngx.shared.DICT:get_keys(max_count?)*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Fetch a list of the keys from the dictionary, up to `<max_count>`.

By default, only the first 1024 keys (if any) are returned. When the `<max_count>` argument is given the value `0`, then all the keys will be returned even there is more than 1024 keys in the dictionary.

**CAUTION** Avoid calling this method on dictionaries with a very large number of keys as it may lock the dictionary for significant amount of time and block Nginx worker processes trying to access the dictionary.

This feature was first introduced in the `v0.7.3` release.

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.capacity
------------------------

**syntax:** *capacity_bytes = ngx.shared.DICT:capacity()*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

**requires:** `resty.core.shdict` or `resty.core`

Retrieves the capacity in bytes for the shm-based dictionary [ngx.shared.DICT](#ngxshareddict) declared with
the [lua_shared_dict](#lua_shared_dict) directive.

Example:

```lua

 require "resty.core.shdict"

 local cats = ngx.shared.cats
 local capacity_bytes = cats:capacity()
```

This feature was first introduced in the `v0.10.11` release.

**Note:** This method requires the `resty.core.shdict` or `resty.core` modules from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library.

This feature requires at least Nginx core version `0.7.3`.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.shared.DICT.free_space
--------------------------

**syntax:** *free_page_bytes = ngx.shared.DICT:free_space()*

**context:** *init_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

**requires:** `resty.core.shdict` or `resty.core`

Retrieves the free page size in bytes for the shm-based dictionary [ngx.shared.DICT](#ngxshareddict).

**Note:** The memory for ngx.shared.DICT is allocated via the Nginx slab allocator which has each slot for
data size ranges like \~8, 9\~16, 17\~32, ..., 1025\~2048, 2048\~ bytes. And pages are assigned to a slot if there
is no room in already assigned pages for the slot.

So even if the return value of the `free_space` method is zero, there may be room in already assigned pages, so
you may successfully set a new key value pair to the shared dict without getting `true` for `forcible` or
non nil `err` from the `ngx.shared.DICT.set`.

On the other hand, if already assigned pages for a slot are full and a new key value pair is added to the
slot and there is no free page, you may get `true` for `forcible` or non nil `err` from the
`ngx.shared.DICT.set` method.

Example:

```lua

 require "resty.core.shdict"

 local cats = ngx.shared.cats
 local free_page_bytes = cats:free_space()
```

This feature was first introduced in the `v0.10.11` release.

**Note:** This method requires the `resty.core.shdict` or `resty.core` modules from the [lua-resty-core](https://github.com/openresty/lua-resty-core) library.

This feature requires at least Nginx core version `1.11.7`.

See also [ngx.shared.DICT](#ngxshareddict).

[Back to TOC](#nginx-api-for-lua)

ngx.socket.udp
--------------

**syntax:** *udpsock = ngx.socket.udp()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Creates and returns a UDP or datagram-oriented unix domain socket object (also known as one type of the "cosocket" objects). The following methods are supported on this object:

* [setpeername](#udpsocksetpeername)
* [send](#udpsocksend)
* [receive](#udpsockreceive)
* [close](#udpsockclose)
* [settimeout](#udpsocksettimeout)

It is intended to be compatible with the UDP API of the [LuaSocket](http://w3.impa.br/~diego/software/luasocket/udp.html) library but is 100% nonblocking out of the box.

This feature was first introduced in the `v0.5.7` release.

See also [ngx.socket.tcp](#ngxsockettcp).

[Back to TOC](#nginx-api-for-lua)

udpsock:setpeername
-------------------

**syntax:** *ok, err = udpsock:setpeername(host, port)*

**syntax:** *ok, err = udpsock:setpeername("unix:/path/to/unix-domain.socket")*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Attempts to connect a UDP socket object to a remote server or to a datagram unix domain socket file. Because the datagram protocol is actually connection-less, this method does not really establish a "connection", but only just set the name of the remote peer for subsequent read/write operations.

Both IP addresses and domain names can be specified as the `host` argument. In case of domain names, this method will use Nginx core's dynamic resolver to parse the domain name without blocking and it is required to configure the [resolver](http://nginx.org/en/docs/http/ngx_http_core_module.html#resolver) directive in the `nginx.conf` file like this:

```nginx

 resolver 8.8.8.8;  # use Google's public DNS nameserver
```

If the nameserver returns multiple IP addresses for the host name, this method will pick up one randomly.

In case of error, the method returns `nil` followed by a string describing the error. In case of success, the method returns `1`.

Here is an example for connecting to a UDP (memcached) server:

```nginx

 location /test {
     resolver 8.8.8.8;

     content_by_lua_block {
         local sock = ngx.socket.udp()
         local ok, err = sock:setpeername("my.memcached.server.domain", 11211)
         if not ok then
             ngx.say("failed to connect to memcached: ", err)
             return
         end
         ngx.say("successfully connected to memcached!")
         sock:close()
     }
 }
```

Since the `v0.7.18` release, connecting to a datagram unix domain socket file is also possible on Linux:

```lua

 local sock = ngx.socket.udp()
 local ok, err = sock:setpeername("unix:/tmp/some-datagram-service.sock")
 if not ok then
     ngx.say("failed to connect to the datagram unix domain socket: ", err)
     return
 end

 -- do something after connect
 -- such as sock:send or sock:receive
```

assuming the datagram service is listening on the unix domain socket file `/tmp/some-datagram-service.sock` and the client socket will use the "autobind" feature on Linux.

Calling this method on an already connected socket object will cause the original connection to be closed first.

This method was first introduced in the `v0.5.7` release.

[Back to TOC](#nginx-api-for-lua)

udpsock:send
------------

**syntax:** *ok, err = udpsock:send(data)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Sends data on the current UDP or datagram unix domain socket object.

In case of success, it returns `1`. Otherwise, it returns `nil` and a string describing the error.

The input argument `data` can either be a Lua string or a (nested) Lua table holding string fragments. In case of table arguments, this method will copy all the string elements piece by piece to the underlying Nginx socket send buffers, which is usually optimal than doing string concatenation operations on the Lua land.

This feature was first introduced in the `v0.5.7` release.

[Back to TOC](#nginx-api-for-lua)

udpsock:receive
---------------

**syntax:** *data, err = udpsock:receive(size?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Receives data from the UDP or datagram unix domain socket object with an optional receive buffer size argument, `size`.

This method is a synchronous operation and is 100% nonblocking.

In case of success, it returns the data received; in case of error, it returns `nil` with a string describing the error.

If the `size` argument is specified, then this method will use this size as the receive buffer size. But when this size is greater than `8192`, then `8192` will be used instead.

If no argument is specified, then the maximal buffer size, `8192` is assumed.

Timeout for the reading operation is controlled by the [lua_socket_read_timeout](#lua_socket_read_timeout) config directive and the [settimeout](#udpsocksettimeout) method. And the latter takes priority. For example:

```lua

 sock:settimeout(1000)  -- one second timeout
 local data, err = sock:receive()
 if not data then
     ngx.say("failed to read a packet: ", err)
     return
 end
 ngx.say("successfully read a packet: ", data)
```

It is important here to call the [settimeout](#udpsocksettimeout) method *before* calling this method.

This feature was first introduced in the `v0.5.7` release.

[Back to TOC](#nginx-api-for-lua)

udpsock:close
-------------

**syntax:** *ok, err = udpsock:close()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Closes the current UDP or datagram unix domain socket. It returns the `1` in case of success and returns `nil` with a string describing the error otherwise.

Socket objects that have not invoked this method (and associated connections) will be closed when the socket object is released by the Lua GC (Garbage Collector) or the current client HTTP request finishes processing.

This feature was first introduced in the `v0.5.7` release.

[Back to TOC](#nginx-api-for-lua)

udpsock:settimeout
------------------

**syntax:** *udpsock:settimeout(time)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Set the timeout value in milliseconds for subsequent socket operations (like [receive](#udpsockreceive)).

Settings done by this method takes priority over those config directives, like [lua_socket_read_timeout](#lua_socket_read_timeout).

This feature was first introduced in the `v0.5.7` release.

[Back to TOC](#nginx-api-for-lua)

ngx.socket.stream
-----------------

Just an alias to [ngx.socket.tcp](#ngxsockettcp). If the stream-typed cosocket may also connect to a unix domain
socket, then this API name is preferred.

This API function was first added to the `v0.10.1` release.

[Back to TOC](#nginx-api-for-lua)

ngx.socket.tcp
--------------

**syntax:** *tcpsock = ngx.socket.tcp()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Creates and returns a TCP or stream-oriented unix domain socket object (also known as one type of the "cosocket" objects). The following methods are supported on this object:

* [bind](#tcpsockbind)
* [connect](#tcpsockconnect)
* [setclientcert](#tcpsocksetclientcert)
* [sslhandshake](#tcpsocksslhandshake)
* [send](#tcpsocksend)
* [receive](#tcpsockreceive)
* [close](#tcpsockclose)
* [settimeout](#tcpsocksettimeout)
* [settimeouts](#tcpsocksettimeouts)
* [setoption](#tcpsocksetoption)
* [receiveany](#tcpsockreceiveany)
* [receiveuntil](#tcpsockreceiveuntil)
* [setkeepalive](#tcpsocksetkeepalive)
* [getreusedtimes](#tcpsockgetreusedtimes)

It is intended to be compatible with the TCP API of the [LuaSocket](http://w3.impa.br/~diego/software/luasocket/tcp.html) library but is 100% nonblocking out of the box. Also, we introduce some new APIs to provide more functionalities.

The cosocket object created by this API function has exactly the same lifetime as the Lua handler creating it. So never pass the cosocket object to any other Lua handler (including ngx.timer callback functions) and never share the cosocket object between different Nginx requests.

For every cosocket object's underlying connection, if you do not
explicitly close it (via [close](#tcpsockclose)) or put it back to the connection
pool (via [setkeepalive](#tcpsocksetkeepalive)), then it is automatically closed when one of
the following two events happens:

* the current request handler completes, or
* the Lua cosocket object value gets collected by the Lua GC.

Fatal errors in cosocket operations always automatically close the current
connection (note that, read timeout error is the only error that is
not fatal), and if you call [close](#tcpsockclose) on a closed connection, you will get
the "closed" error.

Starting from the `0.9.9` release, the cosocket object here is full-duplex, that is, a reader "light thread" and a writer "light thread" can operate on a single cosocket object simultaneously (both "light threads" must belong to the same Lua handler though, see reasons above). But you cannot have two "light threads" both reading (or writing or connecting) the same cosocket, otherwise you might get an error like "socket busy reading" when calling the methods of the cosocket object.

This feature was first introduced in the `v0.5.0rc1` release.

See also [ngx.socket.udp](#ngxsocketudp).

[Back to TOC](#nginx-api-for-lua)

tcpsock:bind
------------
**syntax:** *ok, err = tcpsock:bind(address)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;,ssl_session_fetch_by_lua&#42;,ssl_client_hello_by_lua&#42;*

Just like the standard [proxy_bind](http://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_bind) directive, this api makes the outgoing connection to a upstream server originate from the specified local IP address.

Only IP addresses can be specified as the `address` argument.

Here is an example for connecting to a TCP server from the specified local IP address:

```nginx

 location /test {
     content_by_lua_block {
         local sock = ngx.socket.tcp()
         -- assume "192.168.1.10" is the local ip address
         local ok, err = sock:bind("192.168.1.10")
         if not ok then
             ngx.say("failed to bind")
             return
         end
         local ok, err = sock:connect("192.168.1.67", 80)
         if not ok then
             ngx.say("failed to connect server: ", err)
             return
         end
         ngx.say("successfully connected!")
         sock:close()
     }
 }
```

[Back to TOC](#nginx-api-for-lua)

tcpsock:connect
---------------

**syntax:** *ok, err = tcpsock:connect(host, port, options_table?)*

**syntax:** *ok, err = tcpsock:connect("unix:/path/to/unix-domain.socket", options_table?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Attempts to connect a TCP socket object to a remote server or to a stream unix domain socket file without blocking.

Before actually resolving the host name and connecting to the remote backend, this method will always look up the connection pool for matched idle connections created by previous calls of this method (or the [ngx.socket.connect](#ngxsocketconnect) function).

Both IP addresses and domain names can be specified as the `host` argument. In case of domain names, this method will use Nginx core's dynamic resolver to parse the domain name without blocking and it is required to configure the [resolver](http://nginx.org/en/docs/http/ngx_http_core_module.html#resolver) directive in the `nginx.conf` file like this:

```nginx

 resolver 8.8.8.8;  # use Google's public DNS nameserver
```

If the nameserver returns multiple IP addresses for the host name, this method will pick up one randomly.

In case of error, the method returns `nil` followed by a string describing the error. In case of success, the method returns `1`.

Here is an example for connecting to a TCP server:

```nginx

 location /test {
     resolver 8.8.8.8;

     content_by_lua_block {
         local sock = ngx.socket.tcp()
         local ok, err = sock:connect("www.google.com", 80)
         if not ok then
             ngx.say("failed to connect to google: ", err)
             return
         end
         ngx.say("successfully connected to google!")
         sock:close()
     }
 }
```

Connecting to a Unix Domain Socket file is also possible:

```lua

 local sock = ngx.socket.tcp()
 local ok, err = sock:connect("unix:/tmp/memcached.sock")
 if not ok then
     ngx.say("failed to connect to the memcached unix domain socket: ", err)
     return
 end

 -- do something after connect
 -- such as sock:send or sock:receive
```

assuming memcached (or something else) is listening on the unix domain socket file `/tmp/memcached.sock`.

Timeout for the connecting operation is controlled by the [lua_socket_connect_timeout](#lua_socket_connect_timeout) config directive and the [settimeout](#tcpsocksettimeout) method. And the latter takes priority. For example:

```lua

 local sock = ngx.socket.tcp()
 sock:settimeout(1000)  -- one second timeout
 local ok, err = sock:connect(host, port)
```

It is important here to call the [settimeout](#tcpsocksettimeout) method *before* calling this method.

Calling this method on an already connected socket object will cause the original connection to be closed first.

An optional Lua table can be specified as the last argument to this method to specify various connect options:

* `pool`
	specify a custom name for the connection pool being used. If omitted, then the connection pool name will be generated from the string template `"<host>:<port>"` or `"<unix-socket-path>"`.

* `pool_size`
	specify the size of the connection pool. If omitted and no
	`backlog` option was provided, no pool will be created. If omitted
	but `backlog` was provided, the pool will be created with a default
	size equal to the value of the [lua_socket_pool_size](#lua_socket_pool_size)
	directive.
	The connection pool holds up to `pool_size` alive connections
	ready to be reused by subsequent calls to [connect](#tcpsockconnect), but
	note that there is no upper limit to the total number of opened connections
	outside of the pool. If you need to restrict the total number of opened
	connections, specify the `backlog` option.
	When the connection pool would exceed its size limit, the least recently used
	(kept-alive) connection already in the pool will be closed to make room for
	the current connection.
	Note that the cosocket connection pool is per Nginx worker process rather
	than per Nginx server instance, so the size limit specified here also applies
	to every single Nginx worker process. Also note that the size of the connection
	pool cannot be changed once it has been created.
	This option was first introduced in the `v0.10.14` release.

* `backlog`
	if specified, this module will limit the total number of opened connections
	for this pool. No more connections than `pool_size` can be opened
	for this pool at any time. If the connection pool is full, subsequent
	connect operations will be queued into a queue equal to this option's
	value (the "backlog" queue).
	If the number of queued connect operations is equal to `backlog`,
	subsequent connect operations will fail and return `nil` plus the
	error string `"too many waiting connect operations"`.
	The queued connect operations will be resumed once the number of connections
	in the pool is less than `pool_size`.
	The queued connect operation will abort once they have been queued for more
	than `connect_timeout`, controlled by
	[settimeouts](#tcpsocksettimeouts), and will return `nil` plus
	the error string `"timeout"`.
	This option was first introduced in the `v0.10.14` release.

The support for the options table argument was first introduced in the `v0.5.7` release.

This method was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:setclientcert
---------------------

**syntax:** *ok, err = tcpsock:setclientcert(cert, pkey)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Set client certificate chain and corresponding private key to the TCP socket object.
The certificate chain and private key provided will be used later by the [tcpsock:sslhandshake](#tcpsocksslhandshake) method.

* `cert` specify a client certificate chain cdata object that will be used while handshaking with
remote server. These objects can be created using [ngx.ssl.parse\_pem\_cert](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md#parse_pem_cert)
function provided by lua-resty-core. Note that specifying the `cert` option requires
corresponding `pkey` be provided too. See below.
* `pkey` specify a private key corresponds to the `cert` option above.
These objects can be created using [ngx.ssl.parse\_pem\_priv\_key](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md#parse_pem_priv_key)
function provided by lua-resty-core.

If both of `cert` and `pkey` are `nil`, this method will clear any existing client certificate and private key
that was previously set on the cosocket object.

This method was first introduced in the `v0.10.22` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:sslhandshake
--------------------

**syntax:** *session, err = tcpsock:sslhandshake(reused_session?, server_name?, ssl_verify?, send_status_req?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Does SSL/TLS handshake on the currently established connection.

The optional `reused_session` argument can take a former SSL
session userdata returned by a previous `sslhandshake`
call for exactly the same target. For short-lived connections, reusing SSL
sessions can usually speed up the handshake by one order by magnitude but it
is not so useful if the connection pool is enabled. This argument defaults to
`nil`. If this argument takes the boolean `false` value, no SSL session
userdata would return by this call and only a Lua boolean will be returned as
the first return value; otherwise the current SSL session will
always be returned as the first argument in case of successes.

The optional `server_name` argument is used to specify the server
name for the new TLS extension Server Name Indication (SNI). Use of SNI can
make different servers share the same IP address on the server side. Also,
when SSL verification is enabled, this `server_name` argument is
also used to validate the server name specified in the server certificate sent from
the remote.

The optional `ssl_verify` argument takes a Lua boolean value to
control whether to perform SSL verification. When set to `true`, the server
certificate will be verified according to the CA certificates specified by
the [lua_ssl_trusted_certificate](#lua_ssl_trusted_certificate) directive.
You may also need to adjust the [lua_ssl_verify_depth](#lua_ssl_verify_depth)
directive to control how deep we should follow along the certificate chain.
Also, when the `ssl_verify` argument is true and the
`server_name` argument is also specified, the latter will be used
to validate the server name in the server certificate.

The optional `send_status_req` argument takes a boolean that controls whether to send
the OCSP status request in the SSL handshake request (which is for requesting OCSP stapling).

For connections that have already done SSL/TLS handshake, this method returns
immediately.

This method was first introduced in the `v0.9.11` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:send
------------

**syntax:** *bytes, err = tcpsock:send(data)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Sends data without blocking on the current TCP or Unix Domain Socket connection.

This method is a synchronous operation that will not return until *all* the data has been flushed into the system socket send buffer or an error occurs.

In case of success, it returns the total number of bytes that have been sent. Otherwise, it returns `nil` and a string describing the error.

The input argument `data` can either be a Lua string or a (nested) Lua table holding string fragments. In case of table arguments, this method will copy all the string elements piece by piece to the underlying Nginx socket send buffers, which is usually optimal than doing string concatenation operations on the Lua land.

Timeout for the sending operation is controlled by the [lua_socket_send_timeout](#lua_socket_send_timeout) config directive and the [settimeout](#tcpsocksettimeout) method. And the latter takes priority. For example:

```lua

 sock:settimeout(1000)  -- one second timeout
 local bytes, err = sock:send(request)
```

It is important here to call the [settimeout](#tcpsocksettimeout) method *before* calling this method.

In case of any connection errors, this method always automatically closes the current connection.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:receive
---------------

**syntax:** *data, err, partial = tcpsock:receive(size)*

**syntax:** *data, err, partial = tcpsock:receive(pattern?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Receives data from the connected socket according to the reading pattern or size.

This method is a synchronous operation just like the [send](#tcpsocksend) method and is 100% nonblocking.

In case of success, it returns the data received; in case of error, it returns `nil` with a string describing the error and the partial data received so far.

If a number-like argument is specified (including strings that look like numbers), then it is interpreted as a size. This method will not return until it reads exactly this size of data or an error occurs.

If a non-number-like string argument is specified, then it is interpreted as a "pattern". The following patterns are supported:

* `'*a'`: reads from the socket until the connection is closed. No end-of-line translation is performed;
* `'*l'`: reads a line of text from the socket. The line is terminated by a `Line Feed` (LF) character (ASCII 10), optionally preceded by a `Carriage Return` (CR) character (ASCII 13). The CR and LF characters are not included in the returned line. In fact, all CR characters are ignored by the pattern.

If no argument is specified, then it is assumed to be the pattern `'*l'`, that is, the line reading pattern.

Timeout for the reading operation is controlled by the [lua_socket_read_timeout](#lua_socket_read_timeout) config directive and the [settimeout](#tcpsocksettimeout) method. And the latter takes priority. For example:

```lua

 sock:settimeout(1000)  -- one second timeout
 local line, err, partial = sock:receive()
 if not line then
     ngx.say("failed to read a line: ", err)
     return
 end
 ngx.say("successfully read a line: ", line)
```

It is important here to call the [settimeout](#tcpsocksettimeout) method *before* calling this method.

Since the `v0.8.8` release, this method no longer automatically closes the current connection when the read timeout error happens. For other connection errors, this method always automatically closes the connection.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:receiveany
------------------

**syntax:** *data, err = tcpsock:receiveany(max)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns any data received by the connected socket, at most `max` bytes.

This method is a synchronous operation just like the [send](#tcpsocksend) method and is 100% nonblocking.

In case of success, it returns the data received; in case of error, it returns `nil` with a string describing the error.

If the received data is more than this size, this method will return with exactly this size of data.
The remaining data in the underlying receive buffer could be returned in the next reading operation.

Timeout for the reading operation is controlled by the [lua_socket_read_timeout](#lua_socket_read_timeout) config directive and the [settimeouts](#tcpsocksettimeouts) method. And the latter takes priority. For example:

```lua

 sock:settimeouts(1000, 1000, 1000)  -- one second timeout for connect/read/write
 local data, err = sock:receiveany(10 * 1024) -- read any data, at most 10K
 if not data then
     ngx.say("failed to read any data: ", err)
     return
 end
 ngx.say("successfully read: ", data)
```

This method doesn't automatically close the current connection when the read timeout error occurs. For other connection errors, this method always automatically closes the connection.

This feature was first introduced in the `v0.10.14` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:receiveuntil
--------------------

**syntax:** *iterator = tcpsock:receiveuntil(pattern, options?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

This method returns an iterator Lua function that can be called to read the data stream until it sees the specified pattern or an error occurs.

Here is an example for using this method to read a data stream with the boundary sequence `--abcedhb`:

```lua

 local reader = sock:receiveuntil("\r\n--abcedhb")
 local data, err, partial = reader()
 if not data then
     ngx.say("failed to read the data stream: ", err)
 end
 ngx.say("read the data stream: ", data)
```

When called without any argument, the iterator function returns the received data right *before* the specified pattern string in the incoming data stream. So for the example above, if the incoming data stream is `'hello, world! -agentzh\r\n--abcedhb blah blah'`, then the string `'hello, world! -agentzh'` will be returned.

In case of error, the iterator function will return `nil` along with a string describing the error and the partial data bytes that have been read so far.

The iterator function can be called multiple times and can be mixed safely with other cosocket method calls or other iterator function calls.

The iterator function behaves differently (i.e., like a real iterator) when it is called with a `size` argument. That is, it will read that `size` of data on each invocation and will return `nil` at the last invocation (either sees the boundary pattern or meets an error). For the last successful invocation of the iterator function, the `err` return value will be `nil` too. The iterator function will be reset after the last successful invocation that returns `nil` data and `nil` error. Consider the following example:

```lua

 local reader = sock:receiveuntil("\r\n--abcedhb")

 while true do
     local data, err, partial = reader(4)
     if not data then
         if err then
             ngx.say("failed to read the data stream: ", err)
             break
         end

         ngx.say("read done")
         break
     end
     ngx.say("read chunk: [", data, "]")
 end
```

Then for the incoming data stream `'hello, world! -agentzh\r\n--abcedhb blah blah'`, we shall get the following output from the sample code above:


    read chunk: [hell]
    read chunk: [o, w]
    read chunk: [orld]
    read chunk: [! -a]
    read chunk: [gent]
    read chunk: [zh]
    read done


Note that, the actual data returned *might* be a little longer than the size limit specified by the `size` argument when the boundary pattern has ambiguity for streaming parsing. Near the boundary of the data stream, the data string actually returned could also be shorter than the size limit.

Timeout for the iterator function's reading operation is controlled by the [lua_socket_read_timeout](#lua_socket_read_timeout) config directive and the [settimeout](#tcpsocksettimeout) method. And the latter takes priority. For example:

```lua

 local readline = sock:receiveuntil("\r\n")

 sock:settimeout(1000)  -- one second timeout
 line, err, partial = readline()
 if not line then
     ngx.say("failed to read a line: ", err)
     return
 end
 ngx.say("successfully read a line: ", line)
```

It is important here to call the [settimeout](#tcpsocksettimeout) method *before* calling the iterator function (note that the `receiveuntil` call is irrelevant here).

As from the `v0.5.1` release, this method also takes an optional `options` table argument to control the behavior. The following options are supported:

* `inclusive`

The `inclusive` takes a boolean value to control whether to include the pattern string in the returned data string. Default to `false`. For example,

```lua

 local reader = tcpsock:receiveuntil("_END_", { inclusive = true })
 local data = reader()
 ngx.say(data)
```

Then for the input data stream `"hello world _END_ blah blah blah"`, then the example above will output `hello world _END_`, including the pattern string `_END_` itself.

Since the `v0.8.8` release, this method no longer automatically closes the current connection when the read timeout error happens. For other connection errors, this method always automatically closes the connection.

This method was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:close
-------------

**syntax:** *ok, err = tcpsock:close()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Closes the current TCP or stream unix domain socket. It returns the `1` in case of success and returns `nil` with a string describing the error otherwise.

Note that there is no need to call this method on socket objects that have invoked the [setkeepalive](#tcpsocksetkeepalive) method because the socket object is already closed (and the current connection is saved into the built-in connection pool).

Socket objects that have not invoked this method (and associated connections) will be closed when the socket object is released by the Lua GC (Garbage Collector) or the current client HTTP request finishes processing.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:settimeout
------------------

**syntax:** *tcpsock:settimeout(time)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Set the timeout value in milliseconds for subsequent socket operations ([connect](#tcpsockconnect), [receive](#tcpsockreceive), and iterators returned from [receiveuntil](#tcpsockreceiveuntil)).

Settings done by this method take priority over those specified via config directives (i.e. [lua_socket_connect_timeout](#lua_socket_connect_timeout), [lua_socket_send_timeout](#lua_socket_send_timeout), and [lua_socket_read_timeout](#lua_socket_read_timeout)).

Note that this method does *not* affect the [lua_socket_keepalive_timeout](#lua_socket_keepalive_timeout) setting; the `timeout` argument to the [setkeepalive](#tcpsocksetkeepalive) method should be used for this purpose instead.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:settimeouts
-------------------

**syntax:** *tcpsock:settimeouts(connect_timeout, send_timeout, read_timeout)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Respectively sets the connect, send, and read timeout thresholds (in milliseconds) for subsequent socket
operations ([connect](#tcpsockconnect), [send](#tcpsocksend), [receive](#tcpsockreceive), and iterators returned from [receiveuntil](#tcpsockreceiveuntil)).

Settings done by this method take priority over those specified via config directives (i.e. [lua_socket_connect_timeout](#lua_socket_connect_timeout), [lua_socket_send_timeout](#lua_socket_send_timeout), and [lua_socket_read_timeout](#lua_socket_read_timeout)).

It is recommended to use [settimeouts](#tcpsocksettimeouts) instead of [settimeout](#tcpsocksettimeout).

Note that this method does *not* affect the [lua_socket_keepalive_timeout](#lua_socket_keepalive_timeout) setting; the `timeout` argument to the [setkeepalive](#tcpsocksetkeepalive) method should be used for this purpose instead.

This feature was first introduced in the `v0.10.7` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:setoption
-----------------

**syntax:** *ok, err = tcpsock:setoption(option, value?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

This function is added for [LuaSocket](http://w3.impa.br/~diego/software/luasocket/tcp.html) API compatibility, its functionality is implemented `v0.10.18`.

This feature was first introduced in the `v0.5.0rc1` release.

In case of success, it returns `true`. Otherwise, it returns nil and a string describing the error.

The `option` is a string with the option name, and the value depends on the option being set:

* `keepalive`

	Setting this option to true enables sending of keep-alive messages on
	connection-oriented sockets. Make sure the `connect` function
	had been called before, for example,

    ```lua

    local ok, err = tcpsock:setoption("keepalive", true)
    if not ok then
        ngx.say("setoption keepalive failed: ", err)
    end
    ```
* `reuseaddr`

	Enabling this option indicates that the rules used in validating addresses
	supplied in a call to bind should allow reuse of local addresses. Make sure
	the `connect` function had been called before, for example,

    ```lua

    local ok, err = tcpsock:setoption("reuseaddr", 0)
    if not ok then
        ngx.say("setoption reuseaddr failed: ", err)
    end
    ```
* `tcp-nodelay`

	Setting this option to true disables the Nagle's algorithm for the connection.
	Make sure the `connect` function had been called before, for example,

    ```lua

    local ok, err = tcpsock:setoption("tcp-nodelay", true)
    if not ok then
        ngx.say("setoption tcp-nodelay failed: ", err)
    end
    ```
* `sndbuf`

	Sets the maximum socket send buffer in bytes. The kernel doubles this value
	(to allow space for bookkeeping overhead) when it is set using setsockopt().
	Make sure the `connect` function had been called before, for example,

    ```lua

    local ok, err = tcpsock:setoption("sndbuf", 1024 * 10)
    if not ok then
        ngx.say("setoption sndbuf failed: ", err)
    end
    ```
* `rcvbuf`

	Sets the maximum socket receive buffer in bytes. The kernel doubles this value
	(to allow space for bookkeeping overhead) when it is set using setsockopt. Make
	sure the `connect` function had been called before, for example,

    ```lua

    local ok, err = tcpsock:setoption("rcvbuf", 1024 * 10)
    if not ok then
        ngx.say("setoption rcvbuf failed: ", err)
    end
    ```

NOTE: Once the option is set, it will become effective until the connection is closed. If you know the connection is from the connection pool and all the in-pool connections already have called the setoption() method with the desired socket option state, then you can just skip calling setoption() again to avoid the overhead of repeated calls, for example,

```lua

 local count, err = tcpsock:getreusedtimes()
 if not count then
     ngx.say("getreusedtimes failed: ", err)
     return
 end

 if count == 0 then
     local ok, err = tcpsock:setoption("rcvbuf", 1024 * 10)
     if not ok then
         ngx.say("setoption rcvbuf failed: ", err)
         return
     end
 end
```

These options described above are supported in `v0.10.18`, and more options will be implemented in future.

[Back to TOC](#nginx-api-for-lua)

tcpsock:setkeepalive
--------------------

**syntax:** *ok, err = tcpsock:setkeepalive(timeout?, size?)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Puts the current socket's connection immediately into the cosocket built-in connection pool and keep it alive until other [connect](#tcpsockconnect) method calls request it or the associated maximal idle timeout is expired.

The first optional argument, `timeout`, can be used to specify the maximal idle timeout (in milliseconds) for the current connection. If omitted, the default setting in the [lua_socket_keepalive_timeout](#lua_socket_keepalive_timeout) config directive will be used. If the `0` value is given, then the timeout interval is unlimited.

The second optional argument `size` is considered deprecated since
the `v0.10.14` release of this module, in favor of the
`pool_size` option of the [connect](#tcpsockconnect) method.
Since the `v0.10.14` release, this option will only take effect if
the call to [connect](#tcpsockconnect) did not already create a connection
pool.
When this option takes effect (no connection pool was previously created by
[connect](#tcpsockconnect)), it will specify the size of the connection pool,
and create it.
If omitted (and no pool was previously created), the default size is the value
of the [lua_socket_pool_size](#lua_socket_pool_size) directive.
The connection pool holds up to `size` alive connections ready to be
reused by subsequent calls to [connect](#tcpsockconnect), but note that there
is no upper limit to the total number of opened connections outside of the
pool.
When the connection pool would exceed its size limit, the least recently used
(kept-alive) connection already in the pool will be closed to make room for
the current connection.
Note that the cosocket connection pool is per Nginx worker process rather
than per Nginx server instance, so the size limit specified here also applies
to every single Nginx worker process. Also note that the size of the connection
pool cannot be changed once it has been created.
If you need to restrict the total number of opened connections, specify both
the `pool_size` and `backlog` option in the call to
[connect](#tcpsockconnect).

In case of success, this method returns `1`; otherwise, it returns `nil` and a string describing the error.

When the system receive buffer for the current connection has unread data, then this method will return the "connection in dubious state" error message (as the second return value) because the previous session has unread data left behind for the next session and the connection is not safe to be reused.

This method also makes the current cosocket object enter the "closed" state, so there is no need to manually call the [close](#tcpsockclose) method on it afterwards.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

tcpsock:getreusedtimes
----------------------

**syntax:** *count, err = tcpsock:getreusedtimes()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

This method returns the (successfully) reused times for the current connection. In case of error, it returns `nil` and a string describing the error.

If the current connection does not come from the built-in connection pool, then this method always returns `0`, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

ngx.socket.connect
------------------

**syntax:** *tcpsock, err = ngx.socket.connect(host, port)*

**syntax:** *tcpsock, err = ngx.socket.connect("unix:/path/to/unix-domain.socket")*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;*

This function is a shortcut for combining [ngx.socket.tcp()](#ngxsockettcp) and the [connect()](#tcpsockconnect) method call in a single operation. It is actually implemented like this:

```lua

 local sock = ngx.socket.tcp()
 local ok, err = sock:connect(...)
 if not ok then
     return nil, err
 end
 return sock
```

There is no way to use the [settimeout](#tcpsocksettimeout) method to specify connecting timeout for this method and the [lua_socket_connect_timeout](#lua_socket_connect_timeout) directive must be set at configure time instead.

This feature was first introduced in the `v0.5.0rc1` release.

[Back to TOC](#nginx-api-for-lua)

ngx.get_phase
-------------

**syntax:** *str = ngx.get_phase()*

**context:** *init_by_lua&#42;, init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Retrieves the current running phase name. Possible return values are

* `init`
	for the context of [init_by_lua*](#init_by_lua).
* `init_worker`
	for the context of [init_worker_by_lua*](#init_worker_by_lua).
* `ssl_cert`
	for the context of [ssl_certificate_by_lua*](#ssl_certificate_by_lua_block).
* `ssl_session_fetch`
	for the context of [ssl_session_fetch_by_lua*](#ssl_session_fetch_by_lua_block).
* `ssl_session_store`
	for the context of [ssl_session_store_by_lua*](#ssl_session_store_by_lua_block).
* `ssl_client_hello`
	for the context of [ssl_client_hello_by_lua*](#ssl_client_hello_by_lua_block).
* `set`
	for the context of [set_by_lua*](#set_by_lua).
* `rewrite`
	for the context of [rewrite_by_lua*](#rewrite_by_lua).
* `balancer`
	for the context of [balancer_by_lua*](#balancer_by_lua_block).
* `access`
	for the context of [access_by_lua*](#access_by_lua).
* `content`
	for the context of [content_by_lua*](#content_by_lua).
* `header_filter`
	for the context of [header_filter_by_lua*](#header_filter_by_lua).
* `body_filter`
	for the context of [body_filter_by_lua*](#body_filter_by_lua).
* `log`
	for the context of [log_by_lua*](#log_by_lua).
* `timer`
	for the context of user callback functions for [ngx.timer.*](#ngxtimerat).
* `exit_worker`
	for the context of [exit_worker_by_lua*](#exit_worker_by_lua).

This API was first introduced in the `v0.5.10` release.

[Back to TOC](#nginx-api-for-lua)

ngx.thread.spawn
----------------

**syntax:** *co = ngx.thread.spawn(func, arg1, arg2, ...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Spawns a new user "light thread" with the Lua function `func` as well as those optional arguments `arg1`, `arg2`, and etc. Returns a Lua thread (or Lua coroutine) object represents this "light thread".

"Light threads" are just a special kind of Lua coroutines that are scheduled by the ngx_lua module.

Before `ngx.thread.spawn` returns, the `func` will be called with those optional arguments until it returns, aborts with an error, or gets yielded due to I/O operations via the [Nginx API for Lua](#nginx-api-for-lua) (like [tcpsock:receive](#tcpsockreceive)).

After `ngx.thread.spawn` returns, the newly-created "light thread" will keep running asynchronously usually at various I/O events.

All the Lua code chunks running by [rewrite_by_lua](#rewrite_by_lua), [access_by_lua](#access_by_lua), and [content_by_lua](#content_by_lua) are in a boilerplate "light thread" created automatically by ngx_lua. Such boilerplate "light thread" are also called "entry threads".

By default, the corresponding Nginx handler (e.g., [rewrite_by_lua](#rewrite_by_lua) handler) will not terminate until

1. both the "entry thread" and all the user "light threads" terminates,
1. a "light thread" (either the "entry thread" or a user "light thread") aborts by calling [ngx.exit](#ngxexit), [ngx.exec](#ngxexec), [ngx.redirect](#ngxredirect), or [ngx.req.set_uri(uri, true)](#ngxreqset_uri), or
1. the "entry thread" terminates with a Lua error.

When the user "light thread" terminates with a Lua error, however, it will not abort other running "light threads" like the "entry thread" does.

Due to the limitation in the Nginx subrequest model, it is not allowed to abort a running Nginx subrequest in general. So it is also prohibited to abort a running "light thread" that is pending on one ore more Nginx subrequests. You must call [ngx.thread.wait](#ngxthreadwait) to wait for those "light thread" to terminate before quitting the "world". A notable exception here is that you can abort pending subrequests by calling [ngx.exit](#ngxexit) with and only with the status code `ngx.ERROR` (-1), `408`, `444`, or `499`.

The "light threads" are not scheduled in a pre-emptive way. In other words, no time-slicing is performed automatically. A "light thread" will keep running exclusively on the CPU until

1. a (nonblocking) I/O operation cannot be completed in a single run,
1. it calls [coroutine.yield](#coroutineyield) to actively give up execution, or
1. it is aborted by a Lua error or an invocation of [ngx.exit](#ngxexit), [ngx.exec](#ngxexec), [ngx.redirect](#ngxredirect), or [ngx.req.set_uri(uri, true)](#ngxreqset_uri).

For the first two cases, the "light thread" will usually be resumed later by the ngx_lua scheduler unless a "stop-the-world" event happens.

User "light threads" can create "light threads" themselves. And normal user coroutines created by [coroutine.create](#coroutinecreate) can also create "light threads". The coroutine (be it a normal Lua coroutine or a "light thread") that directly spawns the "light thread" is called the "parent coroutine" for the "light thread" newly spawned.

The "parent coroutine" can call [ngx.thread.wait](#ngxthreadwait) to wait on the termination of its child "light thread".

You can call coroutine.status() and coroutine.yield() on the "light thread" coroutines.

The status of the "light thread" coroutine can be "zombie" if

1. the current "light thread" already terminates (either successfully or with an error),
1. its parent coroutine is still alive, and
1. its parent coroutine is not waiting on it with [ngx.thread.wait](#ngxthreadwait).

The following example demonstrates the use of coroutine.yield() in the "light thread" coroutines
to do manual time-slicing:

```lua

 local yield = coroutine.yield

 function f()
     local self = coroutine.running()
     ngx.say("f 1")
     yield(self)
     ngx.say("f 2")
     yield(self)
     ngx.say("f 3")
 end

 local self = coroutine.running()
 ngx.say("0")
 yield(self)

 ngx.say("1")
 ngx.thread.spawn(f)

 ngx.say("2")
 yield(self)

 ngx.say("3")
 yield(self)

 ngx.say("4")
```

Then it will generate the output


    0
    1
    f 1
    2
    f 2
    3
    f 3
    4


"Light threads" are mostly useful for making concurrent upstream requests in a single Nginx request handler, much like a generalized version of [ngx.location.capture_multi](#ngxlocationcapture_multi) that can work with all the [Nginx API for Lua](#nginx-api-for-lua). The following example demonstrates parallel requests to MySQL, Memcached, and upstream HTTP services in a single Lua handler, and outputting the results in the order that they actually return (similar to Facebook's BigPipe model):

```lua

 -- query mysql, memcached, and a remote http service at the same time,
 -- output the results in the order that they
 -- actually return the results.

 local mysql = require "resty.mysql"
 local memcached = require "resty.memcached"

 local function query_mysql()
     local db = mysql:new()
     db:connect{
                 host = "127.0.0.1",
                 port = 3306,
                 database = "test",
                 user = "monty",
                 password = "mypass"
               }
     local res, err, errno, sqlstate =
             db:query("select * from cats order by id asc")
     db:set_keepalive(0, 100)
     ngx.say("mysql done: ", cjson.encode(res))
 end

 local function query_memcached()
     local memc = memcached:new()
     memc:connect("127.0.0.1", 11211)
     local res, err = memc:get("some_key")
     ngx.say("memcached done: ", res)
 end

 local function query_http()
     local res = ngx.location.capture("/my-http-proxy")
     ngx.say("http done: ", res.body)
 end

 ngx.thread.spawn(query_mysql)      -- create thread 1
 ngx.thread.spawn(query_memcached)  -- create thread 2
 ngx.thread.spawn(query_http)       -- create thread 3
```

This API was first enabled in the `v0.7.0` release.

[Back to TOC](#nginx-api-for-lua)

ngx.thread.wait
---------------

**syntax:** *ok, res1, res2, ... = ngx.thread.wait(thread1, thread2, ...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Waits on one or more child "light threads" and returns the results of the first "light thread" that terminates (either successfully or with an error).

The arguments `thread1`, `thread2`, and etc are the Lua thread objects returned by earlier calls of [ngx.thread.spawn](#ngxthreadspawn).

The return values have exactly the same meaning as [coroutine.resume](#coroutineresume), that is, the first value returned is a boolean value indicating whether the "light thread" terminates successfully or not, and subsequent values returned are the return values of the user Lua function that was used to spawn the "light thread" (in case of success) or the error object (in case of failure).

Only the direct "parent coroutine" can wait on its child "light thread", otherwise a Lua exception will be raised.

The following example demonstrates the use of `ngx.thread.wait` and [ngx.location.capture](#ngxlocationcapture) to emulate [ngx.location.capture_multi](#ngxlocationcapture_multi):

```lua

 local capture = ngx.location.capture
 local spawn = ngx.thread.spawn
 local wait = ngx.thread.wait
 local say = ngx.say

 local function fetch(uri)
     return capture(uri)
 end

 local threads = {
     spawn(fetch, "/foo"),
     spawn(fetch, "/bar"),
     spawn(fetch, "/baz")
 }

 for i = 1, #threads do
     local ok, res = wait(threads[i])
     if not ok then
         say(i, ": failed to run: ", res)
     else
         say(i, ": status: ", res.status)
         say(i, ": body: ", res.body)
     end
 end
```

Here it essentially implements the "wait all" model.

And below is an example demonstrating the "wait any" model:

```lua

 function f()
     ngx.sleep(0.2)
     ngx.say("f: hello")
     return "f done"
 end

 function g()
     ngx.sleep(0.1)
     ngx.say("g: hello")
     return "g done"
 end

 local tf, err = ngx.thread.spawn(f)
 if not tf then
     ngx.say("failed to spawn thread f: ", err)
     return
 end

 ngx.say("f thread created: ", coroutine.status(tf))

 local tg, err = ngx.thread.spawn(g)
 if not tg then
     ngx.say("failed to spawn thread g: ", err)
     return
 end

 ngx.say("g thread created: ", coroutine.status(tg))

 ok, res = ngx.thread.wait(tf, tg)
 if not ok then
     ngx.say("failed to wait: ", res)
     return
 end

 ngx.say("res: ", res)

 -- stop the "world", aborting other running threads
 ngx.exit(ngx.OK)
```

And it will generate the following output:


    f thread created: running
    g thread created: running
    g: hello
    res: g done


This API was first enabled in the `v0.7.0` release.

[Back to TOC](#nginx-api-for-lua)

ngx.thread.kill
---------------

**syntax:** *ok, err = ngx.thread.kill(thread)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Kills a running "light thread" created by [ngx.thread.spawn](#ngxthreadspawn). Returns a true value when successful or `nil` and a string describing the error otherwise.

According to the current implementation, only the parent coroutine (or "light thread") can kill a thread. Also, a running "light thread" with pending Nginx subrequests (initiated by [ngx.location.capture](#ngxlocationcapture) for example) cannot be killed due to a limitation in the Nginx core.

This API was first enabled in the `v0.9.9` release.

[Back to TOC](#nginx-api-for-lua)

ngx.on_abort
------------

**syntax:** *ok, err = ngx.on_abort(callback)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

Registers a user Lua function as the callback which gets called automatically when the client closes the (downstream) connection prematurely.

Returns `1` if the callback is registered successfully or returns `nil` and a string describing the error otherwise.

All the [Nginx API for Lua](#nginx-api-for-lua) can be used in the callback function because the function is run in a special "light thread", just as those "light threads" created by [ngx.thread.spawn](#ngxthreadspawn).

The callback function can decide what to do with the client abortion event all by itself. For example, it can simply ignore the event by doing nothing and the current Lua request handler will continue executing without interruptions. And the callback function can also decide to terminate everything by calling [ngx.exit](#ngxexit), for example,

```lua

 local function my_cleanup()
     -- custom cleanup work goes here, like cancelling a pending DB transaction

     -- now abort all the "light threads" running in the current request handler
     ngx.exit(499)
 end

 local ok, err = ngx.on_abort(my_cleanup)
 if not ok then
     ngx.log(ngx.ERR, "failed to register the on_abort callback: ", err)
     ngx.exit(500)
 end
```

When [lua_check_client_abort](#lua_check_client_abort) is set to `off` (which is the default), then this function call will always return the error message "lua_check_client_abort is off".

According to the current implementation, this function can only be called once in a single request handler; subsequent calls will return the error message "duplicate call".

This API was first introduced in the `v0.7.4` release.

See also [lua_check_client_abort](#lua_check_client_abort).

[Back to TOC](#nginx-api-for-lua)

ngx.timer.at
------------

**syntax:** *hdl, err = ngx.timer.at(delay, callback, user_arg1, user_arg2, ...)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Creates an Nginx timer with a user callback function as well as optional user arguments.

The first argument, `delay`, specifies the delay for the timer,
in seconds. One can specify fractional seconds like `0.001` to mean 1
millisecond here. `0` delay can also be specified, in which case the
timer will immediately expire when the current handler yields
execution.

The second argument, `callback`, can
be any Lua function, which will be invoked later in a background
"light thread" after the delay specified. The user callback will be
called automatically by the Nginx core with the arguments `premature`,
`user_arg1`, `user_arg2`, and etc, where the `premature`
argument takes a boolean value indicating whether it is a premature timer
expiration or not(for the `0` delay timer it is always `false`), and `user_arg1`, `user_arg2`, and etc, are
those (extra) user arguments specified when calling `ngx.timer.at`
as the remaining arguments.

Premature timer expiration happens when the Nginx worker process is
trying to shut down, as in an Nginx configuration reload triggered by
the `HUP` signal or in an Nginx server shutdown. When the Nginx worker
is trying to shut down, one can no longer call `ngx.timer.at` to
create new timers with nonzero delays and in that case `ngx.timer.at` will return a "conditional false" value and
a string describing the error, that is, "process exiting".

Starting from the `v0.9.3` release, it is allowed to create zero-delay timers even when the Nginx worker process starts shutting down.

When a timer expires, the user Lua code in the timer callback is
running in a "light thread" detached completely from the original
request creating the timer. So objects with the same lifetime as the
request creating them, like [cosockets](#ngxsockettcp), cannot be shared between the
original request and the timer user callback function.

Here is a simple example:

```nginx

 location / {
     ...
     log_by_lua_block {
         local function push_data(premature, uri, args, status)
             -- push the data uri, args, and status to the remote
             -- via ngx.socket.tcp or ngx.socket.udp
             -- (one may want to buffer the data in Lua a bit to
             -- save I/O operations)
         end
         local ok, err = ngx.timer.at(0, push_data,
                                      ngx.var.uri, ngx.var.args, ngx.header.status)
         if not ok then
             ngx.log(ngx.ERR, "failed to create timer: ", err)
             return
         end

         -- other job in log_by_lua_block
     }
 }
```

One can also create infinite re-occurring timers, for instance, a timer getting triggered every `5` seconds, by calling `ngx.timer.at` recursively in the timer callback function. Here is such an example,

```lua

 local delay = 5
 local handler
 handler = function (premature)
     -- do some routine job in Lua just like a cron job
     if premature then
         return
     end
     local ok, err = ngx.timer.at(delay, handler)
     if not ok then
         ngx.log(ngx.ERR, "failed to create the timer: ", err)
         return
     end

     -- do something in timer
 end

 local ok, err = ngx.timer.at(delay, handler)
 if not ok then
     ngx.log(ngx.ERR, "failed to create the timer: ", err)
     return
 end

 -- do other jobs
```

It is recommended, however, to use the [ngx.timer.every](#ngxtimerevery) API function
instead for creating recurring timers since it is more robust.

Because timer callbacks run in the background and their running time
will not add to any client request's response time, they can easily
accumulate in the server and exhaust system resources due to either
Lua programming mistakes or just too much client traffic. To prevent
extreme consequences like crashing the Nginx server, there are
built-in limitations on both the number of "pending timers" and the
number of "running timers" in an Nginx worker process. The "pending
timers" here mean timers that have not yet been expired and "running
timers" are those whose user callbacks are currently running.

The maximal number of pending timers allowed in an Nginx
worker is controlled by the [lua_max_pending_timers](#lua_max_pending_timers)
directive. The maximal number of running timers is controlled by the
[lua_max_running_timers](#lua_max_running_timers) directive.

According to the current implementation, each "running timer" will
take one (fake) connection record from the global connection record
list configured by the standard [worker_connections](http://nginx.org/en/docs/ngx_core_module.html#worker_connections) directive in
`nginx.conf`. So ensure that the
[worker_connections](http://nginx.org/en/docs/ngx_core_module.html#worker_connections) directive is set to
a large enough value that takes into account both the real connections
and fake connections required by timer callbacks (as limited by the
[lua_max_running_timers](#lua_max_running_timers) directive).

A lot of the Lua APIs for Nginx are enabled in the context of the timer
callbacks, like stream/datagram cosockets ([ngx.socket.tcp](#ngxsockettcp) and [ngx.socket.udp](#ngxsocketudp)), shared
memory dictionaries ([ngx.shared.DICT](#ngxshareddict)), user coroutines ([coroutine.*](#coroutinecreate)),
user "light threads" ([ngx.thread.*](#ngxthreadspawn)), [ngx.exit](#ngxexit), [ngx.now](#ngxnow)/[ngx.time](#ngxtime),
[ngx.md5](#ngxmd5)/[ngx.sha1_bin](#ngxsha1_bin), are all allowed. But the subrequest API (like
[ngx.location.capture](#ngxlocationcapture)), the [ngx.req.*](#ngxreqstart_time) API, the downstream output API
(like [ngx.say](#ngxsay), [ngx.print](#ngxprint), and [ngx.flush](#ngxflush)) are explicitly disabled in
this context.

You must notice that each timer will be based on a fake request (this fake request is also based on a fake connection). Because Nginx's memory release is based on the connection closure, if you run a lot of APIs that apply for memory resources in a timer, such as [tcpsock:connect](#tcpsockconnect), will cause the accumulation of memory resources. So it is recommended to create a new timer after running several times to release memory resources.

You can pass most of the standard Lua values (nils, booleans, numbers, strings, tables, closures, file handles, and etc) into the timer callback, either explicitly as user arguments or implicitly as upvalues for the callback closure. There are several exceptions, however: you *cannot* pass any thread objects returned by [coroutine.create](#coroutinecreate) and [ngx.thread.spawn](#ngxthreadspawn) or any cosocket objects returned by [ngx.socket.tcp](#ngxsockettcp), [ngx.socket.udp](#ngxsocketudp), and [ngx.req.socket](#ngxreqsocket) because these objects' lifetime is bound to the request context creating them while the timer callback is detached from the creating request's context (by design) and runs in its own (fake) request context. If you try to share the thread or cosocket objects across the boundary of the creating request, then you will get the "no co ctx found" error (for threads) or "bad request" (for cosockets). It is fine, however, to create all these objects inside your timer callback.

Please note that the timer Lua handler has its own copy of the `ngx.ctx` magic
table. It won't share the same `ngx.ctx` with the Lua handler creating the timer.
If you need to pass data from the timer creator to the timer handler, please
use the extra parameters of `ngx.timer.at()`.

This API was first introduced in the `v0.8.0` release.

[Back to TOC](#nginx-api-for-lua)

ngx.timer.every
---------------

**syntax:** *hdl, err = ngx.timer.every(delay, callback, user_arg1, user_arg2, ...)*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the [ngx.timer.at](#ngxtimerat) API function, but

1. `delay` *cannot* be zero,
1. timer will be created every `delay` seconds until the current Nginx worker process starts exiting.

Like [ngx.timer.at](#ngxtimerat), the `callback` argument will be called
automatically with the arguments `premature`, `user_arg1`, `user_arg2`, etc.

When success, returns a "conditional true" value (but not a `true`). Otherwise, returns a "conditional false" value and a string describing the error.

This API also respect the [lua_max_pending_timers](#lua_max_pending_timers) and [lua_max_running_timers](#lua_max_running_timers).

This API was first introduced in the `v0.10.9` release.

[Back to TOC](#nginx-api-for-lua)

ngx.timer.running_count
-----------------------

**syntax:** *count = ngx.timer.running_count()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the number of timers currently running.

This directive was first introduced in the `v0.9.20` release.

[Back to TOC](#nginx-api-for-lua)

ngx.timer.pending_count
-----------------------

**syntax:** *count = ngx.timer.pending_count()*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Returns the number of pending timers.

This directive was first introduced in the `v0.9.20` release.

[Back to TOC](#nginx-api-for-lua)

ngx.config.subsystem
--------------------

**syntax:** *subsystem = ngx.config.subsystem*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

This string field indicates the Nginx subsystem the current Lua environment is based on. For this module, this field always takes the string value `"http"`. For
[ngx_stream_lua_module](https://github.com/openresty/stream-lua-nginx-module#readme), however, this field takes the value `"stream"`.

This field was first introduced in the `0.10.1`.

[Back to TOC](#nginx-api-for-lua)

ngx.config.debug
----------------

**syntax:** *debug = ngx.config.debug*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

This boolean field indicates whether the current Nginx is a debug build, i.e., being built by the `./configure` option `--with-debug`.

This field was first introduced in the `0.8.7`.

[Back to TOC](#nginx-api-for-lua)

ngx.config.prefix
-----------------

**syntax:** *prefix = ngx.config.prefix()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

Returns the Nginx server "prefix" path, as determined by the `-p` command-line option when running the Nginx executable, or the path specified by the `--prefix` command-line option when building Nginx with the `./configure` script.

This function was first introduced in the `0.9.2`.

[Back to TOC](#nginx-api-for-lua)

ngx.config.nginx_version
------------------------

**syntax:** *ver = ngx.config.nginx_version*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

This field take an integral value indicating the version number of the current Nginx core being used. For example, the version number `1.4.3` results in the Lua number 1004003.

This API was first introduced in the `0.9.3` release.

[Back to TOC](#nginx-api-for-lua)

ngx.config.nginx_configure
--------------------------

**syntax:** *str = ngx.config.nginx_configure()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;*

This function returns a string for the Nginx `./configure` command's arguments string.

This API was first introduced in the `0.9.5` release.

[Back to TOC](#nginx-api-for-lua)

ngx.config.ngx_lua_version
--------------------------

**syntax:** *ver = ngx.config.ngx_lua_version*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;*

This field take an integral value indicating the version number of the current `ngx_lua` module being used. For example, the version number `0.9.3` results in the Lua number 9003.

This API was first introduced in the `0.9.3` release.

[Back to TOC](#nginx-api-for-lua)

ngx.worker.exiting
------------------

**syntax:** *exiting = ngx.worker.exiting()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

This function returns a boolean value indicating whether the current Nginx worker process already starts exiting. Nginx worker process exiting happens on Nginx server quit or configuration reload (aka HUP reload).

This API was first introduced in the `0.9.3` release.

[Back to TOC](#nginx-api-for-lua)

ngx.worker.pid
--------------

**syntax:** *pid = ngx.worker.pid()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

This function returns a Lua number for the process ID (PID) of the current Nginx worker process. This API is more efficient than `ngx.var.pid` and can be used in contexts where the [ngx.var.VARIABLE](#ngxvarvariable) API cannot be used (like [init_worker_by_lua](#init_worker_by_lua)).

This API was first introduced in the `0.9.5` release.

[Back to TOC](#nginx-api-for-lua)

ngx.worker.pids
--------------

**syntax:** *pids = ngx.worker.pids()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, exit_worker_by_lua&#42;*

This function returns a Lua table for all Nginx worker process IDs (PIDs). Nginx uses channel to send the current worker PID to another worker in the worker process start or restart. So this API can get all current worker PIDs. Windows does not have this API.

This API was first introduced in the `0.10.23` release.

[Back to TOC](#nginx-api-for-lua)

ngx.worker.count
----------------

**syntax:** *count = ngx.worker.count()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_by_lua&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

Returns the total number of the Nginx worker processes (i.e., the value configured
by the [worker_processes](https://nginx.org/en/docs/ngx_core_module.html#worker_processes)
directive in `nginx.conf`).

This API was first introduced in the `0.9.20` release.

[Back to TOC](#nginx-api-for-lua)

ngx.worker.id
-------------

**syntax:** *id = ngx.worker.id()*

**context:** *set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, init_worker_by_lua&#42;, exit_worker_by_lua&#42;*

Returns the ordinal number of the current Nginx worker processes (starting from number 0).

So if the total number of workers is `N`, then this method may return a number between 0
and `N - 1` (inclusive).

This function returns meaningful values only for Nginx 1.9.1+. With earlier versions of Nginx, it
always returns `nil`.

See also [ngx.worker.count](#ngxworkercount).

This API was first introduced in the `0.9.20` release.

[Back to TOC](#nginx-api-for-lua)

ngx.semaphore
-------------

**syntax:** *local semaphore = require "ngx.semaphore"*

This is a Lua module that implements a classic-style semaphore API for efficient synchronizations among
different "light threads". Sharing the same semaphore among different "light threads" created in different (request)
contexts are also supported as long as the "light threads" reside in the same Nginx worker process
and the [lua_code_cache](#lua_code_cache) directive is turned on (which is the default).

This Lua module does not ship with this ngx_lua module itself rather it is shipped with
the
[lua-resty-core](https://github.com/openresty/lua-resty-core) library.

Please refer to the [documentation](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/semaphore.md)
for this `ngx.semaphore` Lua module in [lua-resty-core](https://github.com/openresty/lua-resty-core)
for more details.

This feature requires at least ngx_lua `v0.10.0`.

[Back to TOC](#nginx-api-for-lua)

ngx.balancer
------------

**syntax:** *local balancer = require "ngx.balancer"*

This is a Lua module that provides a Lua API to allow defining completely dynamic load balancers
in pure Lua.

This Lua module does not ship with this ngx_lua module itself rather it is shipped with
the
[lua-resty-core](https://github.com/openresty/lua-resty-core) library.

Please refer to the [documentation](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md)
for this `ngx.balancer` Lua module in [lua-resty-core](https://github.com/openresty/lua-resty-core)
for more details.

This feature requires at least ngx_lua `v0.10.0`.

[Back to TOC](#nginx-api-for-lua)

ngx.ssl
-------

**syntax:** *local ssl = require "ngx.ssl"*

This Lua module provides API functions to control the SSL handshake process in contexts like
[ssl_certificate_by_lua*](#ssl_certificate_by_lua_block).

This Lua module does not ship with this ngx_lua module itself rather it is shipped with
the
[lua-resty-core](https://github.com/openresty/lua-resty-core) library.

Please refer to the [documentation](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md)
for this `ngx.ssl` Lua module for more details.

This feature requires at least ngx_lua `v0.10.0`.

[Back to TOC](#nginx-api-for-lua)

ngx.ocsp
--------

**syntax:** *local ocsp = require "ngx.ocsp"*

This Lua module provides API to perform OCSP queries, OCSP response validations, and
OCSP stapling planting.

Usually, this module is used together with the [ngx.ssl](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ssl.md)
module in the
context of [ssl_certificate_by_lua*](#ssl_certificate_by_lua_block).

This Lua module does not ship with this ngx_lua module itself rather it is shipped with
the
[lua-resty-core](https://github.com/openresty/lua-resty-core) library.

Please refer to the [documentation](https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/ocsp.md)
for this `ngx.ocsp` Lua module for more details.

This feature requires at least ngx_lua `v0.10.0`.

[Back to TOC](#nginx-api-for-lua)

ndk.set_var.DIRECTIVE
---------------------

**syntax:** *res = ndk.set_var.DIRECTIVE_NAME*

**context:** *init_worker_by_lua&#42;, set_by_lua&#42;, rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, log_by_lua&#42;, ngx.timer.&#42;, balancer_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, exit_worker_by_lua&#42;, ssl_client_hello_by_lua&#42;*

This mechanism allows calling other Nginx C modules' directives that are implemented by [Nginx Devel Kit](https://github.com/simplresty/ngx_devel_kit) (NDK)'s set_var submodule's `ndk_set_var_value`.

For example, the following [set-misc-nginx-module](http://github.com/openresty/set-misc-nginx-module) directives can be invoked this way:

* [set_quote_sql_str](http://github.com/openresty/set-misc-nginx-module#set_quote_sql_str)
* [set_quote_pgsql_str](http://github.com/openresty/set-misc-nginx-module#set_quote_pgsql_str)
* [set_quote_json_str](http://github.com/openresty/set-misc-nginx-module#set_quote_json_str)
* [set_unescape_uri](http://github.com/openresty/set-misc-nginx-module#set_unescape_uri)
* [set_escape_uri](http://github.com/openresty/set-misc-nginx-module#set_escape_uri)
* [set_encode_base32](http://github.com/openresty/set-misc-nginx-module#set_encode_base32)
* [set_decode_base32](http://github.com/openresty/set-misc-nginx-module#set_decode_base32)
* [set_encode_base64](http://github.com/openresty/set-misc-nginx-module#set_encode_base64)
* [set_decode_base64](http://github.com/openresty/set-misc-nginx-module#set_decode_base64)
* [set_encode_hex](http://github.com/openresty/set-misc-nginx-module#set_encode_base64)
* [set_decode_hex](http://github.com/openresty/set-misc-nginx-module#set_decode_base64)
* [set_sha1](http://github.com/openresty/set-misc-nginx-module#set_encode_base64)
* [set_md5](http://github.com/openresty/set-misc-nginx-module#set_decode_base64)

For instance,

```lua

 local res = ndk.set_var.set_escape_uri('a/b')
 -- now res == 'a%2fb'
```

Similarly, the following directives provided by [encrypted-session-nginx-module](http://github.com/openresty/encrypted-session-nginx-module) can be invoked from within Lua too:

* [set_encrypt_session](http://github.com/openresty/encrypted-session-nginx-module#set_encrypt_session)
* [set_decrypt_session](http://github.com/openresty/encrypted-session-nginx-module#set_decrypt_session)

This feature requires the [ngx_devel_kit](https://github.com/simplresty/ngx_devel_kit) module.

[Back to TOC](#nginx-api-for-lua)

coroutine.create
----------------

**syntax:** *co = coroutine.create(f)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Creates a user Lua coroutines with a Lua function, and returns a coroutine object.

Similar to the standard Lua [coroutine.create](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.create) API, but works in the context of the Lua coroutines created by ngx_lua.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first introduced in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

coroutine.resume
----------------

**syntax:** *ok, ... = coroutine.resume(co, ...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Resumes the execution of a user Lua coroutine object previously yielded or just created.

Similar to the standard Lua [coroutine.resume](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.resume) API, but works in the context of the Lua coroutines created by ngx_lua.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first introduced in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

coroutine.yield
---------------

**syntax:** *... = coroutine.yield(...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Yields the execution of the current user Lua coroutine.

Similar to the standard Lua [coroutine.yield](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.yield) API, but works in the context of the Lua coroutines created by ngx_lua.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first introduced in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

coroutine.wrap
--------------

**syntax:** *co = coroutine.wrap(f)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Similar to the standard Lua [coroutine.wrap](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.wrap) API, but works in the context of the Lua coroutines created by ngx_lua.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first introduced in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

coroutine.running
-----------------

**syntax:** *co = coroutine.running()*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Identical to the standard Lua [coroutine.running](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.running) API.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first enabled in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

coroutine.status
----------------

**syntax:** *status = coroutine.status(co)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, init_by_lua&#42;, ngx.timer.&#42;, header_filter_by_lua&#42;, body_filter_by_lua&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;, ssl_session_store_by_lua&#42;, ssl_client_hello_by_lua&#42;*

Identical to the standard Lua [coroutine.status](https://www.lua.org/manual/5.1/manual.html#pdf-coroutine.status) API.

This API was first usable in the context of [init_by_lua*](#init_by_lua) since the `0.9.2`.

This API was first enabled in the `v0.6.0` release.

[Back to TOC](#nginx-api-for-lua)

ngx.run_worker_thread
---------------------

**syntax:** *ok, res1, res2, ... = ngx.run_worker_thread(threadpool, module_name, func_name, arg1, arg2, ...)*

**context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;*

**This API is still experimental and may change in the future without notice.**

**This API is available only for Linux.**

Wrap the [nginx worker thread](http://nginx.org/en/docs/dev/development_guide.html#threads) to execute lua function. The caller coroutine would yield until the function returns.

Only the following ngx_lua APIs could be used in `function_name` function of the `module` module:

* `ngx.encode_base64`
* `ngx.decode_base64`

* `ngx.hmac_sha1`
* `ngx.encode_args`
* `ngx.decode_args`
* `ngx.quote_sql_str`

* `ngx.re.match`
* `ngx.re.find`
* `ngx.re.gmatch`
* `ngx.re.sub`
* `ngx.re.gsub`

* `ngx.crc32_short`
* `ngx.crc32_long`
* `ngx.hmac_sha1`
* `ngx.md5_bin`
* `ngx.md5`

* `ngx.config.subsystem`
* `ngx.config.debug`
* `ngx.config.prefix`
* `ngx.config.nginx_version`
* `ngx.config.nginx_configure`
* `ngx.config.ngx_lua_version`

* `ngx.shared.DICT`

The first argument `threadpool` specifies the Nginx thread pool name defined by [thread_pool](https://nginx.org/en/docs/ngx_core_module.html#thread_pool).

The second argument `module_name` specifies the lua module name to execute in the worker thread, which would return a lua table. The module must be inside the package path, e.g.

```nginx

 lua_package_path '/opt/openresty/?.lua;;';
```

The third argument `func_name` specifies the function field in the module table as the second argument.

The type of `arg`s must be one of type below:

* boolean
* number
* string
* nil
* table (the table may be recursive, and contains members of types above.)

The `ok` is in boolean type, which indicate the C land error (failed to get thread from thread pool, pcall the module function failed, .etc). If `ok` is `false`, the `res1` is the error string.

The return values (res1, ...) are returned by invocation of the module function. Normally, the `res1` should be in boolean type, so that the caller could inspect the error.

This API is useful when you need to execute the below types of tasks:

* CPU bound task, e.g. do md5 calculation
* File I/O task
* Call `os.execute()` or blocking C API via `ffi`
* Call external Lua library not based on cosocket or nginx

Example1: do md5 calculation.

```nginx

 location /calc_md5 {
     default_type 'text/plain';

     content_by_lua_block {
         local ok, md5_or_err = ngx.run_worker_thread("testpool", "md5", "md5")
         ngx.say(ok, " : ", md5_or_err)
     }
 }
```

`md5.lua`

```lua
local function md5()
    return ngx.md5("hello")
end

return { md5=md5, }
```

Example2: write logs into the log file.

```nginx

 location /write_log_file {
     default_type 'text/plain';

     content_by_lua_block {
         local ok, err = ngx.run_worker_thread("testpool", "write_log_file", "log", ngx.var.arg_str)
         if not ok then
             ngx.say(ok, " : ", err)
             return
         end
         ngx.say(ok)
     }
 }
```

`write_log_file.lua`

```lua

 local function log(str)
     local file, err = io.open("/tmp/tmp.log", "a")
     if not file then
         return false, err
     end
     file:write(str)
     file:flush()
     file:close()
     return true
 end
 return {log=log}
```

[Back to TOC](#nginx-api-for-lua)

Obsolete Sections
=================

This section is just holding obsolete documentation sections that have been either renamed or removed so that existing links over the web are still valid.

[Back to TOC](#table-of-contents)

Special PCRE Sequences
----------------------

This section has been renamed to [Special Escaping Sequences](#special-escaping-sequences).

[Back to TOC](#table-of-contents)

Lua/LuaJIT bytecode support
---------------------------

This section has been renamed to
[LuaJIT bytecode support](#luajit-bytecode-support). As of version
`v0.10.16` of this module, the standard Lua interpreter (also known
as "PUC-Rio Lua") is not supported anymore.
