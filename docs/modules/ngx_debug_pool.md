ngx_debug_pool
==============

This module provides access to information of memory usage for nginx/tengine memory pool.

Example
=======

get information of worker process
---------------------------------

```
 http {
    server {
        listen 80;

        location = /debug_pool {
            debug_pool;
        }
    }
 }
```

Requesting URI /debug_pool, you will get information of memory usage for worker process which gets this request.  
The output page may look like as follows:

```
$ curl http://localhost:80/debug_pool
pid:18821
size:      223784 num:           2 cnum:           1 lnum:          10 ngx_init_cycle
size:        1536 num:           4 cnum:           1 lnum:          10 ngx_event_accept
size:           0 num:           1 cnum:           0 lnum:           0 ngx_http_lua_create_fake_request
size:           0 num:           1 cnum:           0 lnum:           0 main
size:           0 num:           1 cnum:           0 lnum:           0 ngx_http_lua_create_fake_connection
size:           0 num:           1 cnum:           0 lnum:           6 ngx_http_server_names
size:        8192 num:           4 cnum:           1 lnum:           0 ngx_http_create_request
size:           0 num:           1 cnum:           0 lnum:           0 ngx_http_lua_init_worker
size:       228KB num:          15 cnum:           3 lnum:          26 [SUMMARY]
```


get information of specific process
-----------------------------------

Also you can use gdb script [debug_pool.gdb](https://github.com/alibaba/tengine/blob/master/modules/ngx_debug_pool/debug_pool.gdb) to get information of specific process.  
Some process cannot handle HTTP request, such as master process or [tengine Proc process](https://github.com/alibaba/tengine/blob/master/docs/modules/ngx_procs_module.md).  
The following example shows how to get information of master process.

```
$ gdb -q -x debug_pool.gdb -p <pid of master process>
(gdb) debug_pool
size:       16384 num:           1 cnum:           1 lnum:           0 ngx_http_user_agent_create_main_conf:24
size:           0 num:           1 cnum:           0 lnum:           0 main:224
size:      150312 num:           2 cnum:           1 lnum:          13 ngx_init_cycle:824
size:      166696 num:           4 cnum:           2 lnum:          13 [SUMMARY]
```

Data
====

Every line except the last one of output content has the same format, as follows:

"__size__: %12u __num__: %12u __cnum__: %12u __lnum__: %12u __\<function name\>__"

* __size__: size of current used memory of this pool
* __num__:  number of created pool (including current used pool and destroyed pool)
* __cnum__: number of current used pool
* __lnum__: number of calling ngx_palloc_large()
* __funcion name__: which nginx/tengine C function creates this pool
  * With function name of pool creator, we can know memory usage of every module, for example:
  * pool created by `ngx_http_create_request` is used for one HTTP request.
    * Because most modules allocates memory from this pool directly, it's hard to distinguish between them.
  * pool created by `ngx_event_accept` is used for one TCP connection.
  * pool created by `ngx_init_cycle` is used for parsing nginx/tengine configuration and keeping other global data structures.
  * pool created by `ngx_http_lua_init_worker` is used for conf.temp_pool of directive [init_worker_by_lua](https://github.com/openresty/lua-nginx-module#init_worker_by_lua).
  * ...

Last line of output content summarizes the information of all memory pools.

Install
=======

```
$ ./configure --add-module=./modules/ngx_debug_pool
$ make && make install
```

Directive
=========

Syntax: **debug_pool**

Default: `none`

Context: `server, location`

The information of nginx/tengine memory pool usage will be accessible from the surrounding location.

Exception
=========

Memory allocated without using memory pool does not get taken into account with this module.  
For example, ngx_http_spdy_module allocates a temporary buffer via malloc(ngx_alloc) for raw data of SYN_REPLY frame. After being compressed, this buffer will be freed immediately.
