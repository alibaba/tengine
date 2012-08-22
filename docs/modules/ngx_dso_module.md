Name
====

* Dynamic Module Loading Support (DSO)

Description
===========

* You can choose which functionalities to include by selecting a set of modules. A module will be compiled as a Dynamic Shared Object (DSO) that exists from the main Tengine binary. So you don't have to recompile Tengine when you want to add or enable a functionality to it.

* If you want to enable an standard module, you should enable it via configure's option while compiling Tengine, for instance, --with-http\_example_module or --with-http\_example_module=shared. Run ./configure --help for more details.

* The maximum of dynamic loaded modules is limited to 128.

* For now, only HTTP modules are dynamic-loaded supported.

* This feature is tested only on Linux/FreeBSD/MacOS.


Example
===========

    worker_processes  1;
    
    dso {
         path /home/nginx-dso/module;

         load ngx_http_lua_module.so;
         load ngx_http_access_module.so;
         load ngx_http_flv_module.so;
         load ngx_http_memcached_module.so;
         load ngx_http_sub_filter_module.so;
         load ngx_http_addition_filter_module.so;
         load ngx_http_footer_filter_module.so;
    }

    events {
       worker_connections  1024;
    }

Directives
==========

include
-------------

**Syntax**: *include file_name*

**Default**: *none*

**Context**: *dso*

Specifies a file contain order of module(via module_order directive).

Example:
    
    include module_order

It will load conf/module_order file and define order of module(via module\_order directive).

load
------------------------

**Syntax**: *load [module_name] [module_path]*

**Default**: *none*

**Context**: *dso*

The load directive loads the object file or library file and adds the specified module to the list of active modules. module\_name is the name of the DSO module, and module\_path is the path of the DSO module.

The order in which the module is searched is as follows:

* the absolute path.
* relative path to the prefix specified by the 'path' directive.
* relative path to the default path (NGX\_PREFIX/modules or path which is specified by the '--dso-path' configure option).


Example:

    load ngx_http_empty_gif_module  ngx_http_empty_gif_module.so;

It will load the ngx\_http\_empty\_gif\_module from ngx\_http\_empty\_gif\_module.so.


module_order
-------------

**Syntax**: *module_order module_name*

**Default**: *none*

**Context**: *dso*


This directive can insert a module into Nginx's module array in order (see conf/module_order for more details). Note it will change the module runtime order. This directive does not need to be used in most cases.

Example:

        module_order ngx_core_module;
        module_order ngx_errlog_module;
        module_order ngx_conf_module;
        module_order ngx_events_module;
        module_order ngx_event_core_module;
        module_order ngx_epoll_module;
        module_order ngx_openssl_module;
        module_order ngx_http_module;
        module_order ngx_http_core_module;
        .......................
        module_order ngx_http_addition_filter_module;
        module_order ngx_http_my_filter_module;

It will insert ngx\_http\_my\_filter\_module before ngx\_http\_addition\_filter\_module.


path
------------------------

**Syntax**: *path path*

**Default**: *none*

**Context**: *dso*

This directive specifies the default path (prefix) for DSO modules.

Example:

    path /home/dso/module;

Sets the default path to /home/dso/module.


Tools
===========

dso_tools
------------------------

This tools can be used to compile a third party nginx module.

Example:

    ./dso_tools --add-module=/home/dso/lua-nginx-module

It will compile the ngx_lua module into a shared object, and install it to the default module path.
