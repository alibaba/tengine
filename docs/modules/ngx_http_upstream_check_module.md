# Name #

**ngx\_http\_upstream\_check\_module**

Add proactive health check for the upstream servers.

This module is not built by default, it should be enabled with the `--with-http_upstream_check_module` configuration parameter.

# Examples #

	http {
		upstream cluster {
			# simple round-robin
			server 192.168.0.1:80;
			server 192.168.0.2:80;

			check interval=3000 rise=2 fall=5 timeout=1000 type=http;
			check_http_send "GET / HTTP/1.0\r\n\r\n";
			check_http_expect_alive http_2xx http_3xx;
		}

		server {
			listen 80;

			location / {
				proxy_pass http://cluster;
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

Syntax: **check** `interval=milliseconds [fall=count] [rise=count] [timeout=milliseconds] [default_down=true|false] [type=tcp|ssl_hello|mysql|ajp]`

Default: If the parameters are omitted, default values are: `interval=30000 fall=5 rise=2 timeout=1000 default_down=true type=tcp`

Context: `upstream`

Add health check for the upstream servers.

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

## check\_http\_send ##

Syntax: **check\_http\_send** `http_packet`

Default: `"GET / HTTP/1.0\r\n\r\n"`

Context: `upstream`

If the check type is http, the check function will send this http packet to the upstream server.

## check\_http\_expect\_alive ##

Syntax: **check\_http\_expect\_alive** `[ http_2xx | http_3xx | http_4xx | http_5xx ]`

Default: `http_2xx | http_3xx`

Context: `upstream`

These status codes indicate the upstream server's http response is OK and the check response is successful.

## check\_shm\_size ##

Syntax: **check\_shm\_size** `size`

Default: `1M`

Context: `http`

Default size is one megabytes. If you want to check thousands of servers, the shared memory may be not enough, you can enlarge it with this directive.

## check\_status ##

Syntax: **check\_status**

Default: `none`

Context: `location`

Display the status of checking servers. This directive should be used in the http block.
