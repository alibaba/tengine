# Core functionality


## Directives

---

> Syntax: **force_exit** exit_time;
> Default: —
> Context: main

force worker processes to exit after exit_time.

The force_exit support is not enabled by default. You should compile it explicitly:

```
 ./configure --with-force-exit
```


---

> Syntax: **worker_processes** [num | auto]
> Default: worker_processes auto
> Context: main

Set the number of worker processes.
When set to 'auto', which is also the default behavior, Tengine will create the same number of worker processes as your CPUs.

---

> Syntax: **worker_cpu_affinity** [mask1 mask2 mask3 ... | auto | off]
> Default: worker_cpu_affinity off
> Context: main

Bind worker processes to the sets of CPUs.
When set to 'auto', Tengine will automatically bind each worker process to a specific CPU. If the number of worker processes is larger than the number of your CPUs, then the rest of worker processes will be bond in descendant order. For example, if there are 8 CPUs in your system: 

*   When the process number set to 4, the binding bitmap will be:

    10000000 01000000 00100000 00010000
*   When the process number set to 8, the binding bitmap will be:

    10000000 01000000 00100000 00010000 00001000 00000100 00000010 00000001
*   When the process number set to 10, the binding bitmap will be:

    10000000 01000000 00100000 00010000 00001000 00000100 00000010 00000001 10000000 01000000

When set to 'off', Tengine will disable the CPU affinity.

---

> Syntax: **error_page** code ... [default] [=[response]]
> Default: -
> Context: http, server, location, if in location

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

---

> Syntax: **request_time_cache** [on | off]
> Default: request_time_cache on
> Context: http, server, location

When set to 'off', Tengine will get a more precise time on $request_time, $request_time_msec, $request_time_usec because it does not use time cache.

---

> Syntax: **log_empty_request** [on | off]
> Default: log_empty_request on
> Context: http, server, location

When you specify it 'off', Tengine will not record any access log when a client issues a connection without any data being sent.
        By default, it's on. In the above case, it will print a 400 Bad Request message into the access log.

---

> Syntax: **server_admin** admin
> Default: none
> Context: http, server, location

Specify the administrator's information, which will appear in a default 4xx/5xx error response when 'server_info' is turned on.

---

> Syntax: **server_info** on | off 
> Default: server_info on
> Context: http, server, location

Show up the server information in a default 4xx/5xx error response. The URL accessed by the user, the hostname serving the request, and the time are included.

---

> Syntax: **server_tag** off | customized_tag 
> Default: none
> Context: http, server, location

Specify the customized 'Server' header in the HTTP responses, for example, 'Apache/2.2.22', 'IIS 6.0', 'Lighttpd', etc. You could also suppress the 'Server' header by setting it to 'off'.

---

> Syntax: **reuse_port** on |  off
> Default: reuse_port off
> Context: events

turn on support for SO_REUSEPORT socket option. This option is supported since Linux 3.9.

[benchmark](benchmark.html)
<!-- [benchmark](../download/reuseport.pdf) -->

