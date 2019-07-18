# Name #

**ngx\_http\_upstream\_check\_module**

Add proactive health check for the upstream servers.

This module is not built by default, it should be enabled with the `--add-module=modules/ngx_http_upstream_check_module` configuration parameter.

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

# Directives #

## check ##

Syntax: **check** `interval=milliseconds [fall=count] [rise=count] [timeout=milliseconds] [default_down=true|false] [type=tcp|http|ssl_hello|mysql|ajp] [port=check_port]`

Default: If the parameters are omitted, default values are: `interval=30000 fall=5 rise=2 timeout=1000 default_down=true type=tcp`

Context: `upstream`

Add health check for the upstream servers.

Passive health checking should not be enabled, as they may interfere. So do not use fail_timeout for the servers in the upstream context for which proactive health checking is enabled.

The parameters' meanings are:

* `interval`: the check request's interval time.
* `fall`(fall\_count): After fall\_count failure checks, the server is marked down.
* `rise`(rise\_count): After rise\_count successful checks, the server is marked up.
* `timeout`: the check request's timeout.
* `default_down`: specify initial state of backend server, default is down.
* `type`: the check protocol type:
 - `tcp`: a simple TCP socket connect and peek one byte.
 - `ssl_hello`: send a client SSL hello packet and receive the server SSL hello packet.
 - `http`: send a http request packet, receive and parse the http response to diagnose if the upstream server is alive.
 - `mysql`: connect to the mysql server, receive the greeting response to diagnose if the upstream server is alive.
 - `ajp`: send an AJP Cping packet, receive and parse the AJP Cpong response to diagnose if the upstream server is alive.
* `port`: specify the check port in the backend servers. It can be different with the original servers port. Default the port is 0 and it means the same as the original backend server. This option is added after tengine-1.4.0.

## check\_keepalive\_requests ##

Syntax: **check\_keepalive\_requests** `request_num`

Default: `1`

Context: `upstream`

The directive specifies the number of requests sent on a connection, the default vaule 1 indicates that tengine will certainly close the connection after a request.

This directive was first introduced in Tengine-2.0.0.

## check\_http\_send ##

Syntax: **check\_http\_send** `http_packet`

Default: `"GET / HTTP/1.0\r\n\r\n"`

Context: `upstream`

If the check type is http, the check function will send this http packet to the upstream server. Method "HEAD" is recommended for reducing traffic.

When persistant connection is used, a keep-alive request header should be added to the value of the directive, e.g. `"HEAD / HTTP/1.1\r\nConnection: keep-alive\r\n\r\n"`.
In addition, in the case of "GET" method, size of the request uri should not be too large, make sure the transmission can be finished within an `interval`, otherwise the health check will deduce a conclusion that there is something wrong with the servers or the net. 

## check\_http\_expect\_alive ##

Syntax: **check\_http\_expect\_alive** `[ http_2xx | http_3xx | http_4xx | http_5xx ]`

Default: `http_2xx http_3xx`

Context: `upstream`

These status codes indicate the upstream server's http response is OK and the check response is successful.

## check\_shm\_size ##

Syntax: **check\_shm\_size** `size`

Default: `1M`

Context: `http`

Default size is one megabytes. If you want to check thousands of servers, the shared memory may be not enough, you can enlarge it with this directive.

## check\_status ##

Syntax: **check\_status** `[html|csv|json]`

Default: `check_status html`

Context: `location`

Display the status of checking servers. This directive should be used in the http block.

You can specify the default display format after Tengine-1.4.0. The formats can be `html`, `csv` or `json`. The default type is `html`. It also supports to specify the format by the request argument. Suppose your `check_status` location is '/status', the argument of `format` can change the display page's format. You can do like this:

    /status?format=html
    /status?format=csv
    /status?format=json

At present, you can fetch the list of servers with the same status by the argument of `status`. For example:

    /status?format=html&status=down
    /status?format=csv&status=up


Below it's the sample html page:

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

Below it's the sample of csv page:

    0,backend,192.168.0.1:80,up,46,0,http,80

Below it's the sample of json page:

    {"servers": {
      "total": 1,
      "generation": 3,
      "server": [
       {"index": 0, "upstream": "backend", "name": "192.168.0.1:80", "status": "up", "rise": 58, "fall": 0, "type": "http", "port": 80}
      ]
     }}

