## Description

This module can be used to update your upstream-list without reloadding Nginx.

## Example

file: conf/nginx.conf

`ATTENTION`: You MUST use nginx variable to do proxy_pass

    daemon off;
    error_log logs/error.log debug;

    events {
    }

    http {

        include conf/upstream.conf;

        server {
            listen   8080;

            location / {
                # The upstream here must be a nginx variable
                proxy_pass http://$host; 
            }
        }

        server {
            listen 8088;
            location / {
                return 200 "8088";
            }
        }

        server {
            listen 8089;
            location / {
                return 200 "8089";
            }
        }

        server {
            listen 8081;
            location / {
                dyups_interface;
            }
        }
    }

If your original config looks like this:

    proxy_pass http://upstream_name;

please replace it with:

    set $ups upstream_name;
    proxy_pass http://$ups;

`$ups` can be any valid nginx variable.

file: conf/upstream.conf

    upstream host1 {
        server 127.0.0.1:8088;
    }

    upstream host2 {
        server 127.0.0.1:8089;
    }


## Installation

* Only install dyups module

```bash
# to compile as a static module
$ ./configure --add-module=./modules/ngx_http_dyups_module

# to compile as a dynamic module
$ ./configure --add-dynamic-module=./modules/ngx_http_dyups_module
```

* Install dyups module with lua-nginx-module and upstream check module
    * upstream check module: To make upstream check module work well with dyups module, you should use `./modules/ngx_http_upstream_check_module`.
    * lua-nginx-module: To enable [dyups LUA API](#lua-api-example), you MUST put `--add-module=./modules/ngx_http_lua_module` in front of `--add-module=./modules/ngx_http_dyups_module` in the `./configure` command.

```bash
# to compile as a static module
$ ./configure --add-module=./modules/nginx_upstream_check_module --add-module=./modules/ngx_http_lua_module --add-module=./modules/ngx_http_dyups_module
```

## Directives

### dyups_interface

Syntax: **dyups_interface**

Default: `none`

Context: `loc`

This directive set the interface location where you can add or delete the upstream list. See the section of Interface for detail.


### dyups_read_msg_timeout

Syntax: **dyups_read_msg_timeout** `time`

Default: `1s`

Context: `main`

This directive set the interval of workers readding the commands from share memory.


### dyups_shm_zone_size

Syntax: **dyups_shm_zone_size** `size`

Default: `2MB`

Context: `main`

This directive set the size of share memory which used to store the commands.


### dyups_upstream_conf

Syntax: **dyups_upstream_conf** `path`

Default: `none`

Context: `main`

This directive has been deprecated


### dyups_trylock

Syntax: **dyups_trylock** `on | off`

Default: `off`

Context: `main`

You will get a better prefomance but it maybe not stable, and you will get a '409' when the update request conflicts with others.


### dyups_read_msg_log

Syntax: **dyups_read_msg_log** `on | off`

Default: `off`

Context: `main`

You can enable / disable log of workers readding the commands from share memory. The log looks like:

```
2017/02/28 15:37:53 [info] 56806#0: [dyups] has 0 upstreams, 1 static, 0 deleted, all 1
```

## restful interface

### GET
- `/detail`         get all upstreams and their servers
- `/list`           get the list of upstreams
- `/upstream/name`  find the upstream by it's name

### POST
- `/upstream/name`  update one upstream
- `body` commands;
- `body` server ip:port;

### DELETE
- `/upstream/name`  delete one upstream

Call the interface, when you get the return code is `HTTP_INTERNAL_SERVER_ERROR 500`, you need to reload nginx to make the Nginx work at a good state.

If you got `HTTP_CONFLICT 409`, you need resend the same commands again latter.

The /list and /detail interface will return `HTTP_NO_CONTENT 204` when there is no upstream.

Other code means you should modify your commands and call the interface again.

`ATTENTION`: You also need a `third-party` to generate the new config and dump it to Nginx'conf directory.

### Sample

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
server 127.0.0.1:8088 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0

host2
server 127.0.0.1:8089 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0

dyhost
server 127.0.0.1:8089 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0
server 127.0.0.1:8088 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0

» curl -i -X DELETE 127.0.0.1:8081/upstream/dyhost
success

» curl 127.0.0.1:8081/detail
host1
server 127.0.0.1:8088 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0

host2
server 127.0.0.1:8089 weight=1 max_conns=0 max_fails=1 fail_timeout=10 backup=0 down=0
```

## C API

```c
extern ngx_flag_t ngx_http_dyups_api_enable;
ngx_int_t ngx_dyups_update_upstream(ngx_str_t *name, ngx_buf_t *buf,
    ngx_str_t *rv);
ngx_int_t ngx_dyups_delete_upstream(ngx_str_t *name, ngx_str_t *rv);

extern ngx_dyups_add_upstream_filter_pt ngx_dyups_add_upstream_top_filter;
extern ngx_dyups_del_upstream_filter_pt ngx_dyups_del_upstream_top_filter;

```

## Lua API Example

NOTICE:
    you should add the directive `dyups_interface` into your config file to active this feature

```lua
content_by_lua '
    local dyups = require "ngx.dyups"

    local status, rv = dyups.update("test", [[server 127.0.0.1:8088;]]);
    ngx.print(status, rv)
    if status ~= ngx.HTTP_OK then
        ngx.print(status, rv)
        return
    end
    ngx.print("update success")

    status, rv = dyups.delete("test")
    if status ~= ngx.HTTP_OK then
        ngx.print(status, rv)
        return
    end
    ngx.print("delete success")
';

```

## Compatibility
### Module Compatibility

* [lua-upstream-nginx-module](https://github.com/agentzh/lua-upstream-nginx-module): You can use `lua-upstream-nginx-module` to get more detail infomation of upstream.
* [upstream check module](http://tengine.taobao.org/document/http_upstream_check.html): To make upstream check module work well with dyups module, you should use `./modules/ngx_http_upstream_check_module`.

