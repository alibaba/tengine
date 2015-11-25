ngx_debug_pool
==============

该模块可以提供nginx/tengine内存池占用内存的状态信息。

示例
====

获取worker进程的信息
--------------------

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

请求URI /debug_pool，可以获取到接受该请求的worker进程的内存使用情况。  
页面输出如下：

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


获取指定进程的信息
------------------

你可以使用gdb脚本[debug_pool.gdb](https://github.com/alibaba/tengine/blob/master/modules/ngx_debug_pool/debug_pool.gdb)来获取指定进程的内存使用情况。  
某些进程无法处理HTTP请求，列如master进程和[tengine Proc 进程](https://github.com/alibaba/tengine/blob/master/docs/modules/ngx_procs_module.md)。  
下面的示例展示如何获取master进程的内存使用情况。

```
$ gdb -q -x debug_pool.gdb -p <pid of master process>
(gdb) debug_pool
size:       16384 num:           1 cnum:           1 lnum:           0 ngx_http_user_agent_create_main_conf:24
size:           0 num:           1 cnum:           0 lnum:           0 main:224
size:      150312 num:           2 cnum:           1 lnum:          13 ngx_init_cycle:824
size:      166696 num:           4 cnum:           2 lnum:          13 [SUMMARY]
```

数据
====

除了最后一行的每一行的输出内容都有相同的格式，如下：

"__size__: %12u __num__: %12u __cnum__: %12u __lnum__: %12u __\<function name\>__"

* __size__: 当前内存池占用的内存
* __num__:  内存池创建的个数（包括当前正在使用的内存池数量和已经被释放的内存池数量）
* __cnum__: 当前正在使用的内存池数量
* __lnum__: 该类内存池调用ngx_palloc_large()次数
* __funcion name__: 创建该内存池的nginx/tengine C函数的函数名
  * 通过创建该内存池的函数的函数名，我们可以知道各个模块的内存使用情况，列如：
  * `ngx_http_create_request`创建的内存池用于HTTP请求。
    * 因为大多数模块直接从该内存池上分配内存，所以很难区分具体哪个模块使用了内存。
  * `ngx_event_accept`创建的内存池用于TCP连接。
  * `ngx_init_cycle`创建的内存池用于解析nginx/tengine的配置和保存其他全局数据结构。
  * `ngx_http_lua_init_worker`用于指令[init_worker_by_lua](https://github.com/openresty/lua-nginx-module#init_worker_by_lua)。
  * ...

最后一行的输出内容汇总了所有内存池的信息。

安装
====

```
$ ./configure --add-module=./modules/ngx_debug_pool
$ make && make install
```

指令
====

Syntax: **debug_pool**

Default: `none`

Context: `server, location`

nginx/tengine的内存池使用信息可以通过该location访问到。

例外
====

不通过内存池分配的内存不会被该模块统计到。  
例如，ngx_http_spdy_module模块会通过malloc(ngx_alloc)为SYN_REPLY帧的生数据分配一块临时缓冲区，该缓冲区在此数据被用于压缩后会被立即释放。
