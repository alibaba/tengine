# 模块名 #
## Proc 模块 ##

提供一个让Tengine可以通过写不同模块启动独立进程的机制。

# 代码实例 #

一个时间回送服务器模块，它运行在一个独立的进程里。

http://tengine.taobao.org/examples/ngx_proc_daytime_module


# 例子 #

    processes {
        process echo {
            eho_str "hello, world";
            echo on;
            listen 8888;
            count 1;
            priority 1;
            delay_start 10s;
            respawn off;
        }

        process example {
            count 1;
            priority 0;
            delay_start 0s;
            respawn on;
        }
    }


# 指令 #

## process ##

Syntax: **process** `name { }`

Default: `none`

Context: `processes`


## count ##

Syntax: **count** `num`

Default: `1`

Context: `process`

指定启动这个进程的数量。


## priority ##

Syntax: **priority** `num`

Default: `0`

Context: `process`

指定进程的优先级(-20 到 20 之间)，越低的数值调度优先级越高。


## delay\_start ##

Syntax: **delay\_start** `time`

Default: `300ms`

Context: `process`

指定延迟启动的时间。


## respawn ##

Syntax: **respawn** `on | off`

Default: `on`

Context: `process`

设置为`on`时，如果进程因为错误意外退出会被Tengine重新启动。
