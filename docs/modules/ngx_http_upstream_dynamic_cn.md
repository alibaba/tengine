模块名
=====

* ngx_http_upstream_dynamic_module

介绍
===

* 此模块提供了在运行时动态解析upstream中server域名的功能

配置示例
=======

    upstream backend {
        dynamic_resolve fallback=stale fail_timeout=30s;

        server a.com;
        server b.com;
    }

    server {
        ...

        proxy_pass http://backend;
    }

指令
===

dynamic_resolve
---------------

**语法**: *dynamic_resolve [fallback=stale|next|shutdown] [fail_timeout=time]*

**默认值**: *-*

**上下文**: *upstream*

指定在某个upstream中启用动态域名解析功能。

fallback参数指定了当域名无法解析时采取的动作：

* stale, 使用tengine启动的时候获取的旧地址
* next, 选择upstream中的下一个server
* shutdown, 结束当前请求

fail_timeout参数指定了一个时间，在这个时间范围内，DNS服务将被当作无法使用。具体来说，就是当某次DNS请求失败后，假定后续多长的时间内DNS服务依然不可用，以减少对无效DNS的查询。
