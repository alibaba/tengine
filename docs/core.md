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



### log pipe
Syntax: **pipe:rollback** [logpath] **interval=**[interval] **baknum=**[baknum] **maxsize=**[maxsize]
Default: none
Context: http, server, location

log pipe module write log use special log proccess, it may not block worker, worker communicate with log proccess use pipe, rollback depend on log pipe module, it support log file auto rollback by tengine self. it support rollback by time and file size, also can configure backup file number. log rollback module will rename log file to backup filename, then reopen the log file and write again

rollback configurge is built-in access_log and error_log：
```
access_log "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize]" proxyformat;

error_log  "pipe:rollback [logpath] interval=[interval] baknum=[baknum] maxsize=[maxsize]" info;
```

logpath: log output file path and name

interval：log rollback interval, default 0 (never)

baknum：backup file number, default 1 (keep 1 backup file)

maxsize：log file max size, default 0 (never)

example：
```
error_log  "pipe:rollback logs/error_log interval=60m baknum=5 maxsize=2048M" info;

http {
	log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
	access_log  "pipe:rollback logs/access_log interval=1h baknum=5 maxsize=2G"  main;
}
```
