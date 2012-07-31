Name
====

* dso module

Description
===========

* On selected operating systems this module can be used to load modules into Tengine at runtime via the DSO (Dynamic Shared Object) mechanism, rather than requiring a recompilation.

* If you want to compile official module with DSO, you should add the configure argument named --with-http\_xxx_module, see the ./configure --help for detail.

* DSO loaded module will limit to 128.

* DSO just support HTTP module;

* This module are tested successfully in Linux/FreeeBSD/MacOS.


Exampe
===========

    worker_processes  1;
    
    dso {
         path /home/nginx-dso/module/;
         load ngx_http_lua_module             ngx_http_lua_module.so;
         load ngx_http_access_module          ngx_http_access_module.so;
         load ngx_http_flv_module             ngx_http_flv_module.so;
         load ngx_http_memcached_module       ngx_http_memcached_module.so;
         load ngx_http_sub_filter_module      ngx_http_sub_filter_module.so;
         load ngx_http_addition_filter_module ngx_http_addition_filter_module.so;
         load ngx_http_footer_filter_module   ngx_http_footer_filter_module.so;
    }

    events {
       worker_connections  1024;
    }

Directives
==========

load
------------------------

**Syntax**: *load module_name module_path*

**Default**: *none*

**Context**: *dso*

The load directive links in the object file or library filename and adds the module structure named module to the list of active modules,module\_name is the name of the DSO module, module\_path is the path of the DSO module.

There are three possibility with the module_path. It will search the module in below order.

1 absolute path.
2 relative to path that path directive.
3 relative to default path(NGX\_PREFIX/modules or path which is specified with --dso-path when configure).


Example:

    load ngx_http_empty_gif_module  ngx_http_empty_gif_module.so;

load empty_gif module from lib\_ngx\_http\_empty\_gif\_module.so.


order
-------------

**Syntax**: *order file*

**Default**: *none*

**Context**: *dso*


This directive can insert your module to nginx' module order list(please see conf/module_order). Be careful, it will change the module runtime order. This directive does not need to be set in most cases.

Example:

     order module_order;
     
in module_order file:
 
        ngx_core_module;
        ngx_errlog_module;
        ngx_conf_module;
        ngx_events_module;
        ngx_event_core_module;
        ngx_epoll_module;
        ngx_openssl_module;
        ngx_http_module;
        ngx_http_core_module;
        .......................
        ngx_http_addition_filter_module;
        ngx_http_my_filter_module;

this will insert my\_filter before addition\_filter module.


path
------------------------

**Syntax**: *path path*

**Default**: *none*

**Context**: *dso*

The dso_path set default path for DSO module

Example:

    path /home/dso/module/;

Set default path to /home/dso/module/.


Tools
===========

dso_tools
------------------------

This tools is used to compile the third nginx'module.

Example:

    ./dso_tools --add-module=/home/dso/lua-nginx-module

This will compile ngx_lua module to dso, and install dso to default module path.
