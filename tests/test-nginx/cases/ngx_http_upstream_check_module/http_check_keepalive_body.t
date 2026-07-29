# vi:filetype=perl

# Regression tests for the keepalive response-body draining fix in
# ngx_http_upstream_check_module: under check_keepalive_requests > 1 the health
# check must fully consume the response body (Content-Length or chunked) before
# the connection is reused, otherwise leftover body bytes are parsed as the next
# check's status line ("check protocol http error") and the peer flaps down.
#
# TEST 5 is the actual reproduction: it delays the tail of the body past the
# check interval, so the leftover bytes land on the reused connection. Without
# the fix that peer goes down after fall=2 checks; with the fix the connection
# is reconnected instead of reused and the peer stays up. The other blocks are
# smoke tests: keepalive checks against a body-serving peer keep it up, the
# default HTTP/1.0 path is unchanged, and a non-2xx response still marks the
# peer down.
#
# Fine-grained parser coverage (Content-Length / chunked / fragmented arrival /
# malformed framing) lives in the C unit tests under
# modules/ngx_http_upstream_check_module/tests/.
#
# Every block waits in "--- init" before requesting: peers start out down
# (default_down defaults to true) and the first check fires after a random delay
# of up to 1s, while the test framework sends its request roughly 100ms after
# the server starts. Without the wait the proxied request races the first check
# and returns 502.

use lib 'lib';
use Test::Nginx::LWP;
use Test::Nginx::Socket;

plan tests => repeat_each(2) * 2 * blocks();

no_root_location();

run_tests();

__DATA__

=== TEST 1: keepalive check drains a Content-Length body, peer stays up
--- http_config
    upstream backend {
        server 127.0.0.1:1970;

        check interval=500 rise=1 fall=2 timeout=1000 type=http;
        check_keepalive_requests 10;
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            return 200 "health-body-with-content-length";
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

--- init: sleep 2;
--- request
GET /
--- response_body chomp
health-body-with-content-length

=== TEST 2: keepalive check drains a large Content-Length body, peer stays up
--- http_config
    upstream backend {
        server 127.0.0.1:1970;

        check interval=500 rise=1 fall=2 timeout=1000 type=http;
        check_keepalive_requests 10;
        check_http_send "GET /big HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        # a multi-hundred-byte body delivered with Content-Length over
        # keepalive; the check must drain all of it before reusing the socket
        location /big {
            return 200 "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        }

        location / {
            return 200 "ok";
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

--- init: sleep 2;
--- request
GET /
--- response_body chomp
ok

=== TEST 3: default HTTP/1.0 non-keepalive path is unchanged (peer up)
--- http_config
    upstream backend {
        server 127.0.0.1:1970;

        check interval=500 rise=1 fall=2 timeout=1000 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

--- init: sleep 2;
--- request
GET /
--- response_body_like: ^<(.*)>$

=== TEST 4: keepalive check against a non-2xx body still marks peer down
--- http_config
    upstream backend {
        server 127.0.0.1:1970;

        # start from up so that the 502 below can only come from the 404 check
        check interval=500 rise=1 fall=1 timeout=1000 type=http default_down=false;
        check_keepalive_requests 10;
        check_http_send "GET /notfound HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        location /notfound {
            return 404 "not-found-body";
        }

        location / {
            return 200 "ok";
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

--- init: sleep 2;
--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$

=== TEST 5: a body whose tail arrives after the next check must not flap the peer
--- http_config
    upstream backend {
        server 127.0.0.1:1970;

        # default_down=false plus fall=2: a peer that starts up can only end up
        # down here if two consecutive checks fail on a polluted connection
        check interval=500 rise=1 fall=2 timeout=1000 type=http default_down=false;
        check_keepalive_requests 10;
        check_http_send "GET /slow HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        # status line and headers arrive at once (limit_rate_after covers them
        # with room to spare), then the body tail dribbles out at 500 bytes/s,
        # i.e. for seconds after the next check has already been sent on the
        # same keepalive connection
        location /slow {
            limit_rate_after 1024;
            limit_rate 500;
            return 200 "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        }

        location / {
            return 200 "still-up";
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

--- init: sleep 3;
--- request
GET /
--- response_body chomp
still-up
