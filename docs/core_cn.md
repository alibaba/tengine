# Core functionality

## 指令

> Syntax: **force_exit** exit_time;
> Default: —
> Context: main

强制worker进程在接受到QUIT信号后 exit_time 时间退出。

force_exit功能默认没有编译开启。需要编译时开启:

```
 ./configure --with-force-exit
```


---

> Syntax: **worker_processes** [num | auto]
> Default: worker_processes auto
> Context: core

为worker_processes增加参数auto。当设置成auto，tengine将自动启动与cpu数量相同的worker进程。

---

> Syntax: **worker_cpu_affinity** [mask1 mask2 mask3 ... | auto | off ]
> Default: worker_cpu_affinity off
> Context: core

为worker_cpu_affinity增加参数auto和off。当设置成auto时，tengine将根据worker的数量自动配置cpu绑定位图。绑定的顺序是按CPU编号从大到小。
如果worker数量大于cpu数量，则剩余的worker进程将按照CPU编号从大到小的顺序从编号最大的CPU开始再次绑定。例如：某CPU有8核，

*   worker数量是4，则自动配置的绑定位图是10000000, 01000000, 00100000, 00010000
*   worker数量是8，则自动配置的绑定位图是10000000, 01000000, 00100000, 00010000, 00001000, 00000100, 00000010, 00000001
*   worker数量是10，则自动配置的绑定位图是10000000, 01000000, 00100000, 00010000, 00001000, 00000100, 00000010, 00000001, 10000000, 01000000

当设置成off时，tengine不会进行cpu绑定。

worker_cpu_affinity的error log最多显示64个CPU的绑定情况。

---

> Syntax: **error_page** code ... [default] [=[response]]
> Default: -
> Context: http, server, location, if in location

该指令用于设置如果出现指定的HTTP错误状态码，返回给客户端显示的对应uri地址。

*   支持default，可以把上一级设置的error_page重新设定；
*   修正error_page不能发现重复的code的问题，不能正常继承上一级设置的问题。

举例：

```
http {
    error_page 404 /404.html;

    server {
        error_page 404 default;
    }
}
```

server中的"error_page"指令将404的页面还原成系统默认。

---

> Syntax: **msie_padding** [on | off]
> Default: msie_padding off
> Context: http, server, location


此指令关闭或开启MSIE浏览器的msie_padding特性，若启用选项，nginx会为response头部填满512字节，这样就阻止了相关浏览器会激活友好错误界面，因此不会隐藏更多的错误信息。Tengine中默认关闭此功能。

---

> Syntax: **request_time_cache** [on | off]
> Default: request_time_cache on
> Context: http, server, location


设置成'off'时，Tengine将不使用时间缓存，$request_time、$request_time_msec和$request_time_usec将会得到更精确的时间。

---

> Syntax: **log_empty_request** [on | off]
> Default: log_empty_request on
> Context: http, server, location


设置成'off'时，Tengine将不会记录没有发送任何数据的访问日志。默认情况下，Tengine会在访问日志里面记录一条400状态的日志。

---

> Syntax: **server_admin** admin
> Default: none
> Context: http, server, location


设置网站管理员信息，当打开server_info的时候，显示错误页面时会显示该信息。

---

> Syntax: **server_info** on | off 
> Default: server_info on
> Context: http, server, location

当打开server_info的时候，显示错误页面时会显示URL、服务器名称和出错时间。

---

> Syntax: **server_tag** off | customized_tag 
> Default: none
> Context: http, server, location


自定义设置HTTP响应的server头，‘off’可以禁止返回server头。如果什么都不设置，就是返回默认Nginx的标识。

---

> Syntax: **reuse_port** on |  off
> Default: reuse_port off
> Context: events


当打开reuse_port的时候，支持SO_REUSEPORT套接字参数，Linux从3.9开始支持。

[测试报告](benchmark_cn.html)
