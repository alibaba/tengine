## 描述
这个模块用来限制用户的并发数以及针对每个用户源ip创建新连接的频率。你也可以通过添加黑白名单的方式来指定IP进行控制。这个模块对于保护HTTPS服务和MAIL服务很有效。

### 配置示例

    error_log logs/error.log debug;
    worker_processes 1;

    events {
        accept_mutex off;
    }

    limit_tcp 8088 8089 rate=1r/m burst=1000 nodelay;
    limit_tcp 8080 rate=1r/m burst=100 name=8080:1M concurrent=1;

    limit_tcp_deny 127.10.0.2/32;
    limit_tcp_deny 127.0.0.1;
    limit_tcp_allow 127.10.0.3;

    http {
        server {
            listen 8088;
            location / {
                return 200;
            }
        }

        server {
            listen 8089;
            location / {
                return 200;
            }
        }

        server {
            listen 8080;
            location / {
                return 200;
            }
        }
    }


## 指令

Syntax: **limit_tcp name:size addr:port [rate= burst= nodelay] [concurrent=]**

Default: `none`

Context: `main`

设置一个共享内存空间和它最大能允许通过的请求频率。如果请求的频率超出了配置的值，那么它将会被延迟处理。如果被延迟的请求数目也超出了burst的配置，那么这个连接将会在创建之后立刻被关闭。

例子:

    limit_tcp 8080 8081 rate=1r/m burst=100 name=share_mem:10M concurrent=10;


Syntax: **limit_tcp_allow address | CIDR | all**

Default: `none`

Context: `main`

允许指定的网段或者ip通过。


Syntax: **limit_tcp_deny address | CIDR | all**

Default: `none`

Context: `main`

拒绝指定的网段或者ip。
