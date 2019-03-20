# Core functionality


## Directives

### force_exit

Syntax: **force_exit** exit_time;

Default: —

Context: main

force worker processes to exit after exit_time.

The force_exit support is not enabled by default. You should compile it explicitly:

```
 ./configure --with-force-exit
```

Note: Removed force_exit directive after the Tengine-2.3.0 version and use Nginx official `worker_shutdown_timeout` , detailed reference [worker_shutdown_timeout](http://nginx.org/en/docs/ngx_core_module.html#worker_shutdown_timeout)


### worker_processes

Syntax: **worker_processes** [num | auto]

Default: worker_processes auto

Context: main

Set the number of worker processes.
When set to 'auto', which is also the default behavior, Tengine will create the same number of worker processes as your CPUs.


### master_env

Syntax: **master_env** variable[=value];

Default: -

Context: main

If use `master_env` directive to set `NGX_DNS_RESOLVE_BACKUP_PATH` environment variable and dns cache will be enabled.
When the dns server is unavailable, it's will use the last dns cache.

For example `master_env NGX_DNS_RESOLVE_BACKUP_PATH=/home/tengine/worker/dnscache/path`, the domain A record results will be saved to the file and path depends on  `NGX_DNS_RESOLVE_BACKUP_PATH`.

### worker_cpu_affinity

Syntax: **worker_cpu_affinity** [mask1 mask2 mask3 ... | auto | off]
Default: worker_cpu_affinity off
Context: main

Bind worker processes to the sets of CPUs.
When set to 'auto', Tengine will automatically bind each worker process to a specific CPU. If the number of worker processes is larger than the number of your CPUs, then the rest of worker processes will be bond in descendant order. For example, if there are 8 CPUs in your system: 

*   When the process number set to 4, the binding bitmap will be:

    10000000 01000000 00100000 00010000
*   When the process number set to 8, the binding bitmap will be:

    10000000 01000000 00100000 00010000 00001000 00000100 00000010 00000001
*   When the process number set to 10, the binding bitmap will be:

    10000000 01000000 00100000 00010000 00001000 00000100 00000010 00000001 10000000 01000000

When set to 'off', Tengine will disable the CPU affinity.


### error_page

Syntax: **error_page** code ... [default] [=[response]]

Default: -

Context: http, server, location, if in location

This directive can specify the page for the specific HTTP response status.

*   Tengine also has a 'default' parameter which can be used to clear the error_page settings in higher level blocks.

For example:

```
    http {
        error_page 404 /404.html;

        server {
            error_page 404 default;
        }
    }
```

In this server block, the 404 error page will be set to Tengine's default 404 page. 


### request_time_cache

Syntax: **request_time_cache** [on | off]

Default: request_time_cache on

Context: http, server, location

When set to 'off', Tengine will get a more precise time on $request_time, $request_time_msec, $request_time_usec because it does not use time cache.


### log_empty_request

Syntax: **log_empty_request** [on | off]

Default: log_empty_request on

Context: http, server, location

When you specify it 'off', Tengine will not record any access log when a client issues a connection without any data being sent.
By default, it's on. In the above case, it will print a 400 Bad Request message into the access log.


### server_admin

Syntax: **server_admin** admin

Default: none

Context: http, server, location

Specify the administrator's information, which will appear in a default 4xx/5xx error response when 'server_info' is turned on.


### server_info

Syntax: **server_info** on | off 

Default: server_info on

Context: http, server, location

Show up the server information in a default 4xx/5xx error response. The URL accessed by the user, the hostname serving the request, and the time are included.


### server_tag

Syntax: **server_tag** off | customized_tag 

Default: none

Context: http, server, location

Specify the customized 'Server' header in the HTTP responses, for example, 'Apache/2.2.22', 'IIS 6.0', 'Lighttpd', etc. You could also suppress the 'Server' header by setting it to 'off'.


### reuse_port

Syntax: **reuse_port** on |  off

Default: reuse_port off

Context: events

turn on support for SO_REUSEPORT socket option. This option is supported since Linux 3.9.

Note:
Removed reuse_port directive after the Tengine-2.3.0 version and use the official reuseport of Nginx, detailed reference [document](https://www.nginx.com/blog/socket-sharding-nginx-release-1-9-1/).

### server_name

Syntax: **server_name** name;

Default: —

Context: server

`server_name` used in Stream module makes Tengine have the ability to listen same ip:port in multiply server blocks and. The connection will be attached to a certain server block by SNI extension in TLS. That means `server_name` should be used with SSL offloading(using `ssl` after `listen`).
The `server_name` support in Stream module is not enabled by default. You should compile it explicitly:

```
 ./configure --with-stream_sni
```
Note:
This feature is experimental. We will deprecate this feature if there is any conflict with similar feature of nginx official.

### ssl_sni_force

Syntax: **ssl_sni_force** on | off

Default: ssl_sni_force off

Context: stream, server

`ssl_sni_force` will determine whether the TLS handsheke is rejected or not if SNI is not matched with server name which we configure by `server_name` in Stream module.

Note:
Same note in `server_name` above.
