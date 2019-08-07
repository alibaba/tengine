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

Syntax: **check** `interval=milliseconds [fall=count] [rise=count] [timeout=milliseconds] [default_down=true|false] [type=tcp|http|ssl_hello|mysql|ajp] [port=check_port]`

Default: 如果没有配置参数，默认值是：`interval=30000 fall=5 rise=2 timeout=1000 default_down=true type=tcp`

Context: `upstream`

该指令可以打开后端服务器的健康检查功能。

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

Syntax: **check\_fastcgi\_params** `parameter`:`value`

Default: `REQUEST_METHOD: GET`
         `REQUEST_URI: /`
         `SCRIPT_FILENAME: index.php'

Context: `upstream`

该指令可以配置fastcgi健康检查包发送的请求的header项。

## check\_http\_expect\_alive ##

Syntax: **check\_http\_expect\_alive** `[ http_2xx | http_3xx | http_4xx | http_5xx ]`

Default: `http_2xx | http_3xx`

Context: `upstream`

该指令指定HTTP回复的成功状态，默认认为2XX和3XX的状态是健康的。

## check\_shm\_size ##

Syntax: **check\_shm\_size** `size`

Default: `1M`

Context: `http`

所有的后端服务器健康检查状态都存于共享内存中，该指令可以设置共享内存的大小。默认是1M，如果你有1千台以上的服务器并在配置的时候出现了错误，就可能需要扩大该内存的大小。

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
            </tr>
        </table>
    </body>
    </html>

下面是csv格式页面的例子：

    0,backend,192.168.0.1:80,up,46,0,http,80

下面是json格式页面的例子：

    {"servers": {
      "total": 1,
      "generation": 3,
      "server": [
       {"index": 0, "upstream": "backend", "name": "106.187.48.116:80", "status": "up", "rise": 58, "fall": 0, "type": "http", "port": 80}
      ]
     }}
