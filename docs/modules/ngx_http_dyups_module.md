Name
====

* ngx_http_dyups_module

Description
===========

This module can be used to update your upstream-list without reloadding Nginx.

TODO:

It can not work with common `nginx_upstream_check_module`.


Compilation
===========

The module is not compiled into Tengine by default. It can be enabled with '--with-http_dyups_module'
configuration parameter, and enabled lua support with '--with-http_dyups_lua_api'.
But it can not be compiled as a '.so'.

Example
==========

file: conf/nginx.conf

    daemon off;
    error_log logs/error.log debug;

    events {
    }

    http {

        dyups_upstream_conf  conf/upstream.conf;

        include conf/upstream.conf;

        server {
            listen   8080;

            location / {
                proxy_pass http://$host;
            }
        }

        server {
            listen 8088;
            location / {
                echo 8088;
            }
        }

        server {
            listen 8089;
            location / {
                echo 8089;
            }
        }

        server {
            listen 8081;
            location / {
                dyups_interface;
            }
        }
    }


file: conf/upstream.conf

    upstream host1 {
        server 127.0.0.1:8088;
    }

    upstream host2 {
        server 127.0.0.1:8089;
    }


Directives
===========

dyups_interface
-------------------------- 

**Syntax**: *dyups_interface*

**Default**: *none*

**Context**: *loc*

This directive set the interface location where you can add or delete the upstream list. See the section of Interface for detail.

dyups_read_msg_timeout
-----------------------------

**Syntax**: *dyups_read_msg_timeout time*

**Default**: *1s*

**Context**: *main*

This directive set the interval of workers readding the commands from share memory.

dyups_shm_zone_size
-----------------------------

**Syntax**: *dyups_shm_zone_size size*

**Default**: *2M*

**Context**: *main*

This directive set the size of share memory which used to store the commands.

dyups_upstream_conf
-----------------------------

**Syntax**: *dyups_upstream_conf path*

**Default**: *none*

**Context**: *main*

This directive set the path of file which you dumped all of upstreams' configs, it will be loaded in `init process` after process respwan to restore upstreams.

dyups_trylock
-----------------------------

**Syntax**: *dyups_trylock on | off* 

**Default**: *off*

**Context**: *main*

You will get a better prefomance but it maybe not stable, and you will get a '409' when the update request conflicts with others.


restful interface
========================

GET
-------------------

* `/detail`         get all upstreams and their servers
* `/list`           get the list of upstreams
* `/upstream/name`  find the upstream by it's name

POST
-------------------

* `/upstream/name`  update one upstream
* `body` commands;
* `body` server ip:port;

DELETE
-------------------
* `/upstream/name`  delete one upstream

Call the interface, when you get the return code is `HTTP_INTERNAL_SERVER_ERROR 500`, you need to reload nginx to make the Nginx work at a good state.

If you got `HTTP_CONFLICT 409`, you need resend the same commands again latter.

The /list and /detail interface will return `HTTP_NO_CONTENT 204` when there is no upstream.

Other code means you should modify your commands and call the interface again.

`ATTENEION`: You also need a `third-party` to generate the new config and dump it to Nginx'conf directory.

Sample
-------------------
```bash
» curl -H "host: dyhost" 127.0.0.1:8080
<html>
<head><title>502 Bad Gateway</title></head>
<body bgcolor="white">
<center><h1>502 Bad Gateway</h1></center>
<hr><center>nginx/1.3.13</center>
</body>
</html>

» curl -d "server 127.0.0.1:8089;server 127.0.0.1:8088;" 127.0.0.1:8081/upstream/dyhost
success

» curl -H "host: dyhost" 127.0.0.1:8080
8089

» curl -H "host: dyhost" 127.0.0.1:8080
8088

» curl 127.0.0.1:8081/detail
host1
server 127.0.0.1:8088

host2
server 127.0.0.1:8089

dyhost
server 127.0.0.1:8089
server 127.0.0.1:8088

» curl -i -X DELETE 127.0.0.1:8081/upstream/dyhost
success

» curl 127.0.0.1:8081/detail
host1
server 127.0.0.1:8088

host2
server 127.0.0.1:8089
```

API
========================

```c
extern ngx_flag_t ngx_http_dyups_api_enable;
ngx_int_t ngx_dyups_update_upstream(ngx_str_t *name, ngx_buf_t *buf,
    ngx_str_t *rv);
ngx_int_t ngx_dyups_delete_upstream(ngx_str_t *name, ngx_str_t *rv);
```

## Lua API Example

NOTICE:
    you should add the directive `dyups_interface` into your config file to active this feature

```lua
content_by_lua '
    local dyups = require "ngx.dyups"

    local status, rv = dyups.update("test", [[server 127.0.0.1:8088;]]);
    ngx.print(status, rv)
    if status ~= 200 then
        ngx.print(status, rv)
        return
    end
    ngx.print("update success")

    status, rv = dyups.delete("test")
    if status ~= 200 then
        ngx.print(status, rv)
        return
    end
    ngx.print("delete success")
';

```
