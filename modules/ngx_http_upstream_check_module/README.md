# ngx_http_upstream_check_module

Tengine ngx_http_upstream_check_module 为 upstream 后端提供**主动**健康检查：按固定间隔
主动探测后端，连续失败达到阈值就把它从负载均衡中摘除，连续成功达到阈值再放回。
七层（`http`）与四层（`stream`）的 upstream 都支持。

与 nginx 原生的**被动**健康检查（`max_fails` / `fail_timeout`）的区别：被动检查要等真实
流量打到故障后端并失败之后才摘除，摘除之前那部分请求已经损失；主动检查在故障发生后的
`interval × fall` 内就能摘除，用户流量不受影响。nginx 官方的主动健康检查是商业版特性，
开源分支只有本模块提供。

* [编译](#编译)
* [快速开始](#快速开始)
* [检查类型](#检查类型)
* [常用参数](#常用参数)
* [状态页](#状态页)
* [排查](#排查)
* [已知限制](#已知限制)

完整的指令语法与参数说明见 [中文文档](../../docs/modules/ngx_http_upstream_check_module_cn.md)
（[English](../../docs/modules/ngx_http_upstream_check_module.md)）；本文侧重可直接套用的
配置示例和实际会踩到的坑。

# 编译

本模块默认不编译，需要显式添加：

```shell
# 只需要七层健康检查
./configure --add-module=modules/ngx_http_upstream_check_module

# 同时需要四层（stream）健康检查
./configure --with-stream --add-module=modules/ngx_http_upstream_check_module
```

带 `--with-stream` 时会额外编出 `ngx_stream_upstream_check_module`，两者共用同一份探测核心、
同一块共享内存和同一个状态页。

**`--with-stream=dynamic` 与本模块不兼容**，configure 阶段即报错：

```
./configure: error: ngx_stream_upstream_check_module does not support building the
stream module dynamically, because it shares the health-check core with
ngx_http_upstream_check_module, which is linked statically.
```

需要 stream 动态模块时只能放弃四层健康检查（去掉本 addon，或去掉 `=dynamic`）。

# 快速开始

## HTTP 七层

`check` 写在 `upstream` 段内，`check_status` 写在 `location` 段内：

```nginx
http {
    upstream backend {
        server 192.168.0.1:80;
        server 192.168.0.2:80;

        # 每 3s 探测一次，连续 2 次成功置为 up，连续 5 次失败置为 down，单次超时 1s
        check interval=3000 rise=2 fall=5 timeout=1000 type=http;
        check_http_send "HEAD / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://backend;
        }

        # 健康状态页，注意做访问控制
        location /upstream_status {
            check_status;

            access_log off;
            allow 127.0.0.1;
            deny all;
        }
    }
}
```

## Stream 四层

四层的 `check` 同样写在 `upstream` 段内。但 `check_status` 是 HTTP 的 location handler，
**只能配在 `http` 段里**；它会把两种模式的后端列在同一个页面上：

```nginx
stream {
    upstream tcp_backend {
        server 192.168.0.1:3306;
        server 192.168.0.2:3306;

        # 四层最常用：探测 TCP 端口能否建连
        check interval=3000 rise=2 fall=5 timeout=1000 type=tcp;
    }

    server {
        listen 3306;
        proxy_pass tcp_backend;
    }
}

http {
    server {
        listen 80;

        # 这个页面同时列出上面 stream 的后端
        location /upstream_status {
            check_status;

            access_log off;
            allow 127.0.0.1;
            deny all;
        }
    }
}
```

如果部署里原本没有 `http` 段，健康检查本身照常工作（探测和摘除都不依赖 `http`），只是没有
状态页可看；需要观测时补一个只含 `check_status` 的 `http` 段即可。

# 检查类型

| `type` | 可用侧 | 探测方式 | 判活依据 |
| --- | --- | --- | --- |
| `tcp` | http / stream | 建立 TCP 连接后 peek 一个字节 | 连接建立成功 |
| `udp` | **仅 stream** | 发送 `check_send`，等回包 | 收到回包，且（若配了）包含 `check_expect_response` |
| `send` | http / stream | 建连后发送 `check_send`，等回包 | 同上 |
| `ssl_hello` | http / stream | 发送 SSLv3 client hello | 收到合法的 server hello |
| `mysql` | http / stream | 建连后等 MySQL greeting | 收到 greeting 包 |
| `http` | 仅 http | 发送 `check_http_send` 指定的请求 | 响应状态码命中 `check_http_expect_alive` |
| `fastcgi` | 仅 http | 发送 FastCGI 请求（`check_fastcgi_param` 定制） | 响应状态码命中 `check_http_expect_alive` |
| `ajp` | 仅 http | 发送 AJP Cping | 收到 Cpong |

在不支持的一侧配置会直接报配置错误，不会静默降级。

## tcp —— TCP 端口探活

最轻量，只关心端口是否能建连，不发送任何业务数据。适合四层代理、以及后端协议本模块不认识
但只需要确认进程存活的场景。

```nginx
# 四层
stream {
    upstream tcp_backend {
        server 192.168.0.1:6379;
        server 192.168.0.2:6379;

        check interval=3000 rise=2 fall=3 timeout=1000 type=tcp;
    }
}

# 七层：后端是 HTTP，但只想探端口、不想产生业务日志
http {
    upstream backend {
        server 192.168.0.1:80;

        check interval=3000 rise=2 fall=5 timeout=1000 type=tcp;
    }
}
```

注意 `tcp` 只能发现「端口不通」，进程假死但端口仍在监听时探测依然成功。对 HTTP 后端优先用
`type=http`，对私有协议后端优先用 `type=send`。

## udp —— UDP 端口探活

**仅 stream 可用。** UDP 没有握手，「端口通不通」在 UDP 上没有意义，所以判活只能依据
「超时之前是否收到回包」：

```nginx
stream {
    # DNS：发一个 example.com 的 A 查询，回包以相同的 transaction id 开头
    upstream dns_cluster {
        server 192.168.0.1:53;
        server 192.168.0.2:53;

        check interval=3000 rise=2 fall=3 timeout=2000 type=udp;
        check_send            "\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01";
        check_expect_response "\x00\x01";
    }

    server {
        listen     53 udp;
        proxy_pass dns_cluster;
    }
}
```

三点必须注意：

* **`type=udp` 必须配 `check_send`。** 不配就什么都不发，对端自然不会回包，于是每次探测都
  超时，后端会被一直判为 down —— 而配置检查不会报错。
* `timeout` 要配得比 TCP 检查宽松。TCP 探测失败往往是立即返回的连接错误，UDP 探测失败只能
  靠超时兜底，`timeout` 直接决定发现故障的耗时。
* 端口完全没有进程监听时通常反而更快被发现：连接态 UDP socket 上的 ICMP port unreachable
  会让本次探测立即失败，不必等到超时。「端口关闭」比「进程静默」判死更快是正常现象。

## send —— 自定义协议探活

发送一段固定字节串，然后在回包中查找期望的字节串。用于本模块不认识的私有协议，
七层四层都可用：

```nginx
# Redis：PING / +PONG
stream {
    upstream redis {
        server 127.0.0.1:6379;

        check interval=3000 rise=2 fall=3 timeout=1000 type=send;
        check_send            "PING\r\n";
        check_expect_response "+PONG";
    }
}
```

`check_send` 与 `check_expect_response` 都接受字节串。配置解析器本身已经支持 `\r`、`\n`、
`\t`、`\\`，本模块额外支持 `\xHH`，所以二进制心跳包也能直接写出来：

```nginx
stream {
    upstream binary_proto {
        server 127.0.0.1:9000;

        check interval=3000 rise=2 fall=3 timeout=1000 type=send;
        # 与上面的 "PING\r\n" 等价，便于表达不可打印字节
        check_send            "\x50\x49\x4e\x47\x0d\x0a";
        check_expect_response "\x2bPONG";
    }
}
```

其他行为：

* 不配 `check_expect_response` 时，**收到任何数据**即判活。适合「只要对端肯说话就算活着」的
  协议，比如连上来就推 banner 的服务。
* 期望字节串出现在回包的任意位置即可，不要求在开头。
* 回包内容不符时不会立即判失败，而是继续等待（期望的字节可能还没收完），最终由 `timeout`
  兜底。所以「回错内容」和「不回内容」的发现耗时都由 `timeout` 决定。
* 不配 `check_send`（只配 `type=send`）在 TCP 上不一定失败：若对端建连后主动发数据仍可判活。
  但语义不清晰，不建议这样用。

## ssl_hello —— TLS 握手探活

发送 SSLv3 client hello 并检查 server hello。用于四层 TLS 直通，或只想确认后端 TLS 栈还能
响应握手：

```nginx
stream {
    upstream tls_passthrough {
        server 192.168.0.1:443;
        server 192.168.0.2:443;

        check interval=3000 rise=2 fall=3 timeout=1000 type=ssl_hello;
    }

    server {
        listen 443;
        proxy_pass tls_passthrough;
    }
}
```

探测只完成到 server hello，不验证证书链，也不做完整握手。

## mysql —— 数据库探活

建连后等待 MySQL 的 greeting 包：

```nginx
stream {
    upstream mysql_cluster {
        server 192.168.0.1:3306;
        server 192.168.0.2:3306;

        check interval=3000 rise=2 fall=3 timeout=1000 type=mysql;
    }

    server {
        listen 3306;
        proxy_pass mysql_cluster;
    }
}
```

比 `type=tcp` 更能说明 mysqld 本身可用，但不代表能登录或执行查询。注意每次探测都会产生一次
连接，MySQL 侧可能记录中断连接的告警。

## http / fastcgi / ajp —— 七层探活

`http` 是七层最常用的类型，按响应状态码判活：

```nginx
http {
    upstream backend {
        server 192.168.0.1:80;
        server 192.168.0.2:80;

        check interval=3000 rise=2 fall=5 timeout=1000 type=http;
        # 推荐 HEAD，减少回包体积
        check_http_send "HEAD /health HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }
}
```

复用连接（长连接探测）可减少建连开销，需要同时给出 `Connection: keep-alive` 和 `Host`：

```nginx
http {
    upstream backend {
        server 192.168.0.1:80;

        check interval=3000 rise=2 fall=5 timeout=1000 type=http;
        check_keepalive_requests 100;
        check_http_send "HEAD /health HTTP/1.1\r\nConnection: keep-alive\r\nHost: foo.bar.com\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }
}
```

FastCGI 后端：

```nginx
http {
    upstream php {
        server 127.0.0.1:9000;

        check interval=3000 rise=2 fall=5 timeout=1000 type=fastcgi;
        check_fastcgi_param "REQUEST_METHOD" "GET";
        check_fastcgi_param "REQUEST_URI" "/ping";
        check_fastcgi_param "SCRIPT_FILENAME" "/var/www/ping.php";
        check_http_expect_alive http_2xx;
    }
}
```

`type=ajp` 用于 AJP 后端（Tomcat 等），发送 Cping 并期待 Cpong，无需额外指令。

# 常用参数

## 探测另一个端口：`port=`

转发端口与探测端口不一致时使用，例如业务在 443、健康检查接口在 8080：

```nginx
upstream backend {
    server 192.168.0.1:443;
    server 192.168.0.2:443;

    check interval=3000 rise=2 fall=5 timeout=1000 type=http port=8080;
    check_http_send "HEAD /health HTTP/1.0\r\n\r\n";
}
```

`port=` 对所有类型都有效。对 unix domain socket 这类没有端口概念的后端，`port=` 会被忽略并
给出告警，该后端仍按自身地址探测（不会被排除在健康检查之外）。

## 起始状态：`default_down`

默认 `default_down=true`，即**启动后所有后端先被视为 down**，要等 `rise` 次成功探测才放入
负载均衡。这是有意的保守设计：避免刚启动时把流量打给尚未确认健康的后端。

代价是启动初期有一个「全部不可用」的窗口：首次探测有最长 `max(interval, 1s)` 的随机延迟
（避免所有后端同时被探测），之后还需 `rise` 次成功。窗口内该 upstream 无可用后端。

不希望有这个窗口时（例如后端确定是健康的、或不能容忍启动抖动）：

```nginx
upstream backend {
    server 192.168.0.1:80;

    check interval=3000 rise=2 fall=5 timeout=1000 type=tcp default_down=false;
}
```

`reload` 不受这个窗口影响：健康状态存在共享内存里，reload 会继承下来，不会退回初始状态。

继承是按后端逐个对应的，判据是「所属 upstream + 注册它的模式（`http` / `stream`）+ 地址」三
者。同一个后端地址被多个 upstream 列出时（也包括 `http` 和 `stream` 里同名的两个 upstream），
每个 upstream 里的这个后端都有自己独立的一份状态，reload 时各自继承各自的，互不影响。唯一的
例外是显式配了 `unique` 的后端，它们本来就共用一份状态。

## 与被动检查的关系

主动检查生效后，不建议再依赖被动检查的参数（`max_fails` / `fail_timeout`）：两者判定口径
不同，叠加后摘除与恢复的时机会变得难以预期。配了 `check` 的 upstream 里建议不再调整
`fail_timeout`。

## 多 worker 与共享内存

同一个后端在同一时刻只由**一个** worker 探测（通过共享内存里的归属标记抢占），因此增加
`worker_processes` 不会成倍放大探测流量。健康状态也存在共享内存里，所有 worker 看到的是
同一份结果。

共享内存的默认大小按后端数量自动推导，另外为运行时动态增删的后端预留 4096 个槽位，一般不
需要手动配置。`check_shm_size` 只用来在此之上再留余量，配成比推导值更小时按推导值走：

```nginx
http {
    check_shm_size 4M;
}
```

`http` 与 `stream` 的后端共用同一块共享内存。两个段里都写了 `check_shm_size` 时取较大值，
不需要分别计算。

# 状态页

`check_status` 支持四种格式，可用指令参数指定默认值，也可用请求参数临时切换：

```nginx
location /upstream_status {
    check_status json;      # 默认格式，可选 html（默认）/ csv / json / prometheus

    access_log off;
    allow 127.0.0.1;
    deny all;
}
```

```shell
curl 'http://127.0.0.1/upstream_status?format=csv'
curl 'http://127.0.0.1/upstream_status?format=json'
curl 'http://127.0.0.1/upstream_status?format=prometheus'

# 只看某一种状态的后端
curl 'http://127.0.0.1/upstream_status?format=csv&status=down'
curl 'http://127.0.0.1/upstream_status?format=csv&status=up'
```

CSV 每行的字段依次为：

```
index,upstream,name,status,rise,fall,type,port,protocol
0,backend,192.168.0.1:80,up,46,0,http,0,http
1,tcp_backend,192.168.0.1:3306,down,0,12,tcp,0,stream
```

| 字段 | 含义 |
| --- | --- |
| `index` | 后端在健康检查表中的序号 |
| `upstream` | 所属 upstream 名 |
| `name` | 后端地址 |
| `status` | `up` / `down` |
| `rise` | 累计连续成功次数（持续累加，可用于判断状态是否被 reload 继承） |
| `fall` | 累计连续失败次数 |
| `type` | 检查类型 |
| `port` | `port=` 指定的探测端口，0 表示与业务端口相同 |
| `protocol` | 该后端由 `http` 还是 `stream` 的 upstream 注册 |

`protocol` 是区分两种模式后端的字段，在所有格式中都追加在末尾（CSV 末列、JSON 末个成员、
prometheus 的额外 label），因此按位置解析旧输出的脚本不受影响。

# 排查

先 `grep check` 过滤 `error_log`。配置类问题在 `tengine -t` 阶段就能发现，探测类问题只在
运行期出现。

| 日志 / 现象 | 原因 | 处置 |
| --- | --- | --- |
| `[emerg] the "http" check type is not supported in stream upstreams` | 在 `stream` 里配了七层专属类型（`http` / `fastcgi` / `ajp`） | 四层改用 `tcp` / `send` / `udp` / `ssl_hello` / `mysql` |
| `[emerg] the "udp" check type is not supported in http upstreams` | 在 `http` 里配了 `type=udp` | `udp` 仅 `stream` 可用 |
| `[emerg] unknown directive "check"` / `"check_shm_size"` / `"check_status"` | 编译时没加本 addon | 按[编译](#编译)重新 configure |
| `[emerg] unknown directive "stream"` | 编译时没带 `--with-stream` | 加上 `--with-stream` 重新 configure |
| `[emerg] invalid check_send, should set [check] first` | `check_send` 写在 `check` 之前 | 调整顺序，`check` 必须先出现 |
| `[emerg] invalid check_send for check type "tcp"` | `check_send` 用在了非 `send`/`udp` 类型上 | 改 `type=send`，或去掉 `check_send` |
| `[emerg] invalid check_http_send for type "tcp"` | `check_http_send` 用在了非 `http` 类型上 | 改 `type=http`，或去掉该指令 |
| `[error] check time out with peer: <addr>` | 探测在 `timeout` 内没有得到可判定的回包 | 后端确实不可用，或 `timeout` 过短；UDP 场景先确认配了 `check_send` |
| `[error] check protocol <type> error with peer: <addr>` | 回包不符合该类型的协议格式 | 核对 `type` 与后端实际协议是否匹配 |
| `[warn] "check" ignores "port=<n>" for peer "unix:..."` | 对 unix socket 配了 `port=` | 正常提示，该后端按自身地址探测 |
| 状态页内容为空（CSV 无行、JSON `"total": 0`） | 配了 `check_status`，但没有任何 upstream 配置 `check` | 给需要检查的 upstream 补上 `check`；状态页只列出被检查的后端 |
| 所有后端一直是 `down`，无任何 `[error]` | 多为 `type=udp` 未配 `check_send`（不发包 → 收不到回包 → 每次超时） | 补 `check_send`；或先用 `type=tcp` 确认端口连通性 |
| 启动初期短暂全部 `down` | `default_down=true` 的正常表现 | 见 [default_down](#起始状态default_down) |

`worker_processes` 较大时，探测日志会被多个 worker 交替写入，排查时可临时设
`worker_processes 1;` 复现，日志会清晰很多。

# 已知限制

* `check_status` 只能配在 `http` 段（它是 HTTP location handler）。只有 `stream` 段的部署
  需要额外补一个 `http` server 才能看到状态页；健康检查本身不受影响。
* 运行时解析的后端不参与主动健康检查，`http` 与 `stream` 两侧都是如此：

  ```nginx
  upstream backend {
      zone backend 1m;
      server example.com:80 resolve;   # 不会被主动探测
      server 192.168.0.1:80;           # 会被主动探测
  }
  ```

  原因是配置解析阶段还没有可探测的地址。这类后端仍受被动检查保护。
* `--with-stream=dynamic` 不支持，见[编译](#编译)。
* 七层专属指令（`check_keepalive_requests`、`check_http_send`、`check_http_expect_alive`、
  `check_fastcgi_param`）在 `stream` 段不提供。
