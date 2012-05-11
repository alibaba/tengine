# Name #

**ngx\_http\_upstream\_check\_module**

# Synopsis #

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

# Description #

Add proactive health check for the upstream servers.

# Directives #

## check ##

**syntax:** `check interval=milliseconds [fall=count] [rise=count] [timeout=milliseconds] [default_down=true|false] [type=tcp|ssl_hello|mysql|ajp]`

**default:** If the parameters are omitted, default values are: `interval=30000 fall=5 rise=2 timeout=1000 default_down=true type=tcp`

**context:** `upstream`

**description:**

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

**syntax:** `check_http_send http_packet`

**default:** `"GET / HTTP/1.0\r\n\r\n"`

**context:** `upstream`

**description:**

If the check type is http, the check function will send this http packet to the upstream server.

## check\_http\_expect\_alive ##

**syntax:** `check_http_expect_alive [ http_2xx | http_3xx | http_4xx | http_5xx ]`

**default:** `http_2xx | http_3xx`

**context:** `upstream`

**description:**

These status codes indicate the upstream server's http response is OK and the check response is successful.

## check\_shm\_size ##

**syntax:** `check_shm_size size`

**default:** `1M`

**context:** `http`

**description:**

Default size is one megabytes. If you want to check thousands of servers, the shared memory may be not enough, you can enlarge it with this directive.

## check\_status ##

**syntax:** `check_status`

**default:** `none`

**context:** `location`

**description:**

Display the status of checking servers. This directive should be used in the http block.
