Name
====

* dso module

Description
===========

* On selected operating systems this module can be used to load modules into Tengine at runtime via the DSO (Dynamic Shared Object) mechanism, rather than requiring a recompilation.

* If you want to compile official module with DSO, you should add the configure argument named --with-http\_xxx_module, see the ./configure --help for detail.

* DSO loaded module will limit to 128.

* This module are tested successfully in Linux/FreeeBSD/MacOS.


Exampe
===========

    dso_path /home/nginx-dso/module/;

    dso_load ngx_http_hat_filter_module  ngx_http_hat_filter_module.so;
    dso_load ngx_http_lua_module   ngx_http_lua_module.so;
    dso_load ngx_http_addition_filter_module ngx_http_addition_filter_module.so;
    dso_load ngx_http_concat_module  ngx_http_concat_module.so;
    dso_load ngx_http_empty_gif_module  ngx_http_empty_gif_module.so;
    dso_load ngx_http_image_filter_module ngx_http_image_filter_module.so;

Directives
==========

dso_order
-------------

**Syntax**: *dso_order {.....}*

**Default**: *none*

**Context**: *main*


This directive can insert your module to nginx' module order list(please see conf/module_order). Be careful, it will change the module runtime order. This directive does not need to be set in most cases.

Example:

     dso_order {
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
    }

this will insert my\_filter before addition\_filter module.


dso_path
------------------------

**Syntax**: *dso_path path*

**Default**: *none*

**Context**: *main*

The dso_path set default path for DSO module

Example:

    dso_path /home/dso/module/;

Set default path to /home/dso/module/.

dso_load
------------------------

**Syntax**: *dso_load module_name module_path*

**Default**: *none*

**Context**: *main*

The dso_load directive links in the object file or library filename and adds the module structure named module to the list of active modules,module\_name is the name of the DSO module, module\_path is the path of the DSO module.

There are three possibility with the module_path. It will search the module in below order.

1 absolute path.
2 relative to path that dso_path directive.
3 relative to default path(NGX\_PREFIX/modules or path which is specified with --dso-path when configure).


Example:

    dso_load ngx_http_empty_gif_module  ngx_http_empty_gif_module.so;

load empty_gif module from lib\_ngx\_http\_empty\_gif\_module.so.


Tools
===========

dso_tools
------------------------

This tools is used to compile the third nginx'module.

Example:

    ./dso_tools --add-module=/home/dso/lua-nginx-module

This will compile ngx_lua module to dso, and install dso to default module path.
