# Name #

**ngx\_http\_upstream\_check\_module**

该模块可以为Tengine提供主动式后端服务器健康检查的功能。

该模块没有默认开启，它可以在配置编译选项的时候开启：`./configure --add-module=modules/ngx_http_upstream_check_module`

# Examples #

    http {
		upstream cluster1 {
			# simple round-robin
			server 192.168.0.1:80;
			server 192.168.0.2:80;

			check interval=3000 rise=2 fall=5 timeout=1000 type=http;
			check_http_send "HEAD / HTTP/1.0\r\n\r\n";
			check_http_expect_alive http_2xx http_3xx;
		}

		upstream cluster2 {
			# simple round-robin
			server 192.168.0.3:80;
			server 192.168.0.4:80;

			check interval=3000 rise=2 fall=5 timeout=1000 type=http;
			check_keepalive_requests 100;
			check_http_send "HEAD / HTTP/1.1\r\nConnection: keep-alive\r\nHost: foo.bar.com\r\n\r\n";
			check_http_expect_alive http_2xx http_3xx;
		}

		server {
			listen 80;

			location /1 {
				proxy_pass http://cluster1;
			}

			location /2 {
				proxy_pass http://cluster2;
			}

			location /status {
				check_status;

				access_log   off;
				allow SOME.IP.ADD.RESS;
				deny all;
			}
		}
	}

# 指令 #

## check ##

Syntax: **check** `interval=milliseconds [fall=count] [rise=count] [timeout=milliseconds] [default_down=true|false] [type=tcp|http|ssl_hello|mysql|ajp|send|udp] [port=check_port]`

Default: 如果没有配置参数，默认值是：`interval=30000 fall=5 rise=2 timeout=1000 default_down=true type=tcp`

Context: `upstream`（`http` 和 `stream` 下均可）

该指令可以打开后端服务器的健康检查功能。

在 `stream` 的 upstream 中只接受与协议无关的检查类型：`tcp`、`ssl_hello`、`mysql`、`send` 和 `udp`。在那里配置 `http`、`fastcgi` 或 `ajp` 会报配置错误；反过来在 `http` 的 upstream 中配置 `udp` 也会报错。详见下面的「stream 四层健康检查」。

指令后面的参数意义是：

* `interval`：向后端发送的健康检查包的间隔。
* `fall`(fall\_count): 如果连续失败次数达到fall\_count，服务器就被认为是down。
* `rise`(rise\_count): 如果连续成功次数达到rise\_count，服务器就被认为是up。
* `timeout`: 后端健康请求的超时时间。
* `default_down`: 设定初始时服务器的状态，如果是true，就说明默认是down的，如果是false，就是up的。默认值是true，也就是一开始服务器认为是不可用，要等健康检查包达到一定成功次数以后才会被认为是健康的。
* `type`：健康检查包的类型，现在支持以下多种类型
 - `tcp`：简单的tcp连接，如果连接成功，就说明后端正常。
 - `ssl_hello`：发送一个初始的SSL hello包并接受服务器的SSL hello包。
 - `http`：发送HTTP请求，通过后端的回复包的状态来判断后端是否存活。
 - `fastcgi`：发送fsatcgi请求，通过后端的回复包的状态来判断后端是否存活。
 - `mysql`: 向mysql服务器连接，通过接收服务器的greeting包来判断后端是否存活。
 - `ajp`：向后端发送AJP协议的Cping包，通过接收Cpong包来判断后端是否存活。
 - `send`：发送 `check_send` 指定的固定字节串，并在回包中查找 `check_expect_response` 指定的字节串。与协议无关，适用于本模块不认识的私有协议。
 - `udp`：`send` 的 UDP 变体，仅 `stream` 可用。详见下面的 `check_send`。
* `port`: 指定后端服务器的检查端口。你可以指定不同于真实服务的后端服务器的端口，比如后端提供的是443端口的应用，你可以去检查80端口的状态来判断后端健康状况。默认是0，表示跟后端server提供真实服务的端口一样。该选项出现于Tengine-1.4.0。


## check\_keepalive\_requests ##

Syntax: **check\_keepalive\_requests** `request_num`

Default: `1`

Context: `upstream`

该指令可以配置一个连接发送的请求数，其默认值为1，表示Tengine完成1次请求后即关闭连接。

该指令在Tengine-2.0.0首次被引入。

## check\_http\_send ##

Syntax: **check\_http\_send** `http_packet`

Default: `"GET / HTTP/1.0\r\n\r\n"`

Context: `upstream`

该指令可以配置http健康检查包发送的请求内容。为了减少传输数据量，推荐采用`"HEAD"`方法。

当采用长连接进行健康检查时，需在该指令中添加keep-alive请求头，如：`"HEAD / HTTP/1.1\r\nConnection: keep-alive\r\n\r\n"`。
同时，在采用`"GET"`方法的情况下，请求uri的size不宜过大，确保可以在1个`interval`内传输完成，否则会被健康检查模块视为后端服务器或网络异常。

## check\_fastcgi\_param ##

Syntax: **check\_fastcgi\_param** `parameter` `value`

Default: `REQUEST_METHOD GET`
         `REQUEST_URI /`
         `SCRIPT_FILENAME index.php`

Context: `upstream`

该指令可以配置fastcgi健康检查包发送的请求的header项。

## check\_send ##

Syntax: **check\_send** `bytes`

Default: 无，默认不发送任何内容

Context: `upstream`（`http` 和 `stream` 下均可）

`send` 与 `udp` 检查类型发送的探测内容。只对这两种类型有效，且必须写在 `check` 之后。

除了配置解析器本身已支持的 `\r`、`\n`、`\t`、`\\` 转义之外，还支持 `\xHH`，因此二进制心跳包也能直接写出来：

    upstream redis {
        server 127.0.0.1:6379;

        check interval=3000 rise=2 fall=3 timeout=1000 type=send;
        check_send            "PING\r\n";
        check_expect_response "+PONG";
    }

对 `type=udp` 需要注意：UDP 没有握手，单纯探测端口说明不了任何问题，因此只能依据 `timeout` 之内是否收到回包来判活。它的 `timeout` 要配得比 TCP 检查宽松。另外，关闭的 UDP 端口通常比静默的端口更快被发现——前者触发的 ICMP port unreachable 会让检查立即失败，而不必等到超时。

## check\_expect\_response ##

Syntax: **check\_expect\_response** `bytes`

Default: 无，默认收到任何回包即认为存活

Context: `upstream`（`http` 和 `stream` 下均可）

`send` 或 `udp` 检查判定存活所需的字节串，出现在回包的任意位置即可。转义规则与 `check_send` 相同。不配置时，只要收到任何数据就算存活。

如果期望的字节始终没有出现，检查会在 `timeout` 到期时失败——也就是说 `timeout` 决定了"回错内容或不回内容"多久被发现。

## check\_http\_expect\_alive ##

Syntax: **check\_http\_expect\_alive** `[ http_2xx | http_3xx | http_4xx | http_5xx ]`

Default: `http_2xx | http_3xx`

Context: `upstream`

该指令指定HTTP回复的成功状态，默认认为2XX和3XX的状态是健康的。

## check\_shm\_size ##

Syntax: **check\_shm\_size** `size`

Default: `1M`

Context: `http`、`stream`

所有的后端服务器健康检查状态都存于共享内存中，该指令可以设置共享内存的大小。默认是1M，如果你有1千台以上的服务器并在配置的时候出现了错误，就可能需要扩大该内存的大小。

`http` 与 `stream` 的后端共用同一块共享内存。若两个块中都配置了该指令，取两者中较大的值。

## check\_status ##

Syntax: **check\_status** `[html|csv|json]`

Default: `check_status html`

Context: `location`

显示服务器的健康状态页面。该指令需要在http块中配置。

在Tengine-1.4.0以后，你可以配置显示页面的格式。支持的格式有: `html`、`csv`、 `json`。默认类型是`html`。

你也可以通过请求的参数来指定格式，假设‘/status’是你状态页面的URL， `format`参数改变页面的格式，比如：

    /status?format=html
    /status?format=csv
    /status?format=json

同时你也可以通过status参数来获取相同服务器状态的列表，比如：

    /status?format=html&status=down
    /status?format=csv&status=up


下面是一个HTML状态页面的例子（server number是后端服务器的数量，generation是Nginx reload的次数。Index是服务器的索引，Upstream是在配置中upstream的名称，Name是服务器IP，Status是服务器的状态，Rise是服务器连续检查成功的次数，Fall是连续检查失败的次数，Check type是检查的方式，Check port是后端专门为健康检查设置的端口）：

    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
    <title>Nginx http upstream check status</title>
    </head>
    <body>
        <h1>Nginx http upstream check status</h1>
        <h2>Check upstream server number: 1, generation: 3</h2>
        <table style="background-color:white" cellspacing="0"        cellpadding="3" border="1">
            <tr bgcolor="#C0C0C0">
                <th>Index</th>
                <th>Upstream</th>
                <th>Name</th>
                <th>Status</th>
                <th>Rise counts</th>
                <th>Fall counts</th>
                <th>Check type</th>
                <th>Check port</th>
                <th>Protocol</th>
            </tr>
            <tr>
                <td>0</td>
                <td>backend</td>
                <td>192.168.0.1:80</td>
                <td>up</td>
                <td>39</td>
                <td>0</td>
                <td>http</td>
                <td>80</td>
                <td>http</td>
            </tr>
        </table>
    </body>
    </html>

下面是csv格式页面的例子：

    0,backend,192.168.0.1:80,up,46,0,http,80,http

下面是json格式页面的例子：

    {"servers": {
      "total": 1,
      "generation": 3,
      "server": [
       {"index": 0, "upstream": "backend", "name": "106.187.48.116:80", "status": "up", "rise": 58, "fall": 0, "type": "http", "port": 80, "protocol": "http"}
      ]
     }}

最后一个 `Protocol` 字段表示该后端是由 `http` 还是 `stream` 的 upstream 注册的。它在所有格式中都追加在末尾（CSV 的末列、JSON 的末个成员、prometheus 的额外 label），因此按位置解析旧输出的脚本不受影响。

# stream 四层健康检查 #

`stream` 的 upstream 同样支持主动健康检查。在此之前 nginx 在四层只提供被动检查（`max_fails` / `fail_timeout`）——只有真实流量已经打到故障后端并失败之后才会摘除。

    stream {
        upstream tcp_cluster {
            server 192.168.0.1:3306;
            server 192.168.0.2:3306;

            check interval=3000 rise=2 fall=5 timeout=1000 type=tcp;
        }

        server {
            listen 3306;
            proxy_pass tcp_cluster;
        }
    }

    http {
        server {
            listen 80;

            # 同一个页面里也会列出上面 stream 的后端
            location /status {
                check_status;

                access_log   off;
                allow SOME.IP.ADD.RESS;
                deny all;
            }
        }
    }

被标记为 down 的后端会被所有 stream 负载均衡算法跳过：round-robin、`hash`、`least_conn`、`random` 和 `least_time`。

UDP 的 upstream 用 `type=udp` 检查：

    stream {
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

需要注意的限制：

* 只接受与协议无关的检查类型：`tcp`、`ssl_hello`、`mysql`、`send`、`udp`。`http`、`fastcgi`、`ajp` 会报配置错误；而 `udp` 只在这里可用，`http` 下不可用。
* `check_status` 是 HTTP 的 location handler，只能配在 `http` 里。如果部署中只有 `stream` 块，需要额外起一个 `http` server 才能查看状态页；该页面会同时列出两类后端。
* `check_keepalive_requests`、`check_http_send`、`check_http_expect_alive`、`check_fastcgi_param` 是 HTTP 专属指令，在 `stream` 中不提供。
* 运行时解析的后端（`server example.com:3306 resolve;`）不参与主动健康检查，`http` 和 `stream` 两侧都是如此：配置解析阶段还没有可探测的地址。
* `stream` 模块必须静态编译。`--with-stream=dynamic` 与本 addon 同时使用会在 configure 阶段被拒绝，因为 stream 侧与静态链接的 HTTP 侧共用同一份健康检查核心。
