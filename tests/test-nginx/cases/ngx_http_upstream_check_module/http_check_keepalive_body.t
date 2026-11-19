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
# TEST 6 covers the other half of the fix -- that the drained connection is then
# genuinely reused. Peer state cannot show this: a discard handler that ignores
# the body framing leaves recv_body_pending set forever, so every check simply
# reconnects and the peer stays up throughout. The block therefore asserts on
# $connection_requests as the backend sees it, which only exceeds 1 once a
# connection survives a check.
#
# Fine-grained parser coverage (Content-Length / chunked / fragmented arrival /
# malformed framing) lives in the C unit tests under
# modules/ngx_http_upstream_check_module/tests/.
#
# TEST 1 to TEST 5 wait in "--- init" before requesting: peers start out down
# (default_down defaults to true) and the first check fires after a random delay
# of up to 1s, while the test framework sends its request roughly 100ms after
# the server starts. Without the wait the proxied request races the first check
# and returns 502. TEST 6 needs its wait on every repeated run instead, so it
# uses "--- wait"; see the comment there.

use lib 'lib';
use Test::Nginx::LWP;
use Test::Nginx::Socket;

# two assertions per block, plus the extra "--- error_log" one in TEST 6
plan tests => repeat_each(2) * (2 * blocks() + 1);

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

=== TEST 6: a drained connection is actually reused by the next check
--- http_config
    # The health check's own requests are logged into error.log -- the file
    # "--- error_log" inspects -- so this block can assert on the reuse itself
    # rather than on the peer's up/down state. That distinction matters: when
    # the discard handler does not track the body, recv_body_pending is never
    # cleared, connect_handler drops the socket and reconnects before every
    # check, and the peer still stays happily up. The only visible difference
    # is on the backend side, where every check then arrives on a brand-new
    # connection and $connection_requests never leaves 1.
    log_format check_conn "healthcheck-conn requests=$connection_requests";

    upstream backend {
        server 127.0.0.1:1970;

        check interval=3000 rise=1 fall=5 timeout=1000 type=http default_down=false;
        check_keepalive_requests 10;
        check_http_send "GET /slow HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 1970;

        # The body must not fit in the first write, or it reaches the check
        # together with the headers, the parser drains it inline, and the
        # discard handler is never exercised -- the very path under test.
        # ngx_http_write_filter allows limit_rate_after + limit_rate * 1 bytes
        # during the first second, i.e. 2048 here, so the ~2700-byte response
        # spills into the next second and its tail lands on the idle
        # connection. The check interval is well past that, so by the time the
        # next check starts the discard handler has finished and the socket is
        # clean: reusable with the fix, always reconnected without it.
        location /slow {
            access_log logs/error.log check_conn;

            limit_rate_after 1024;
            limit_rate 1024;
            return 200 "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
        }

        location / {
            return 200 "still-up";
        }
    }

--- config
    location / {
        proxy_pass http://backend;
    }

# "--- wait" rather than "--- init": the wait has to happen on every repeated
# run, and "--- init" is evaluated once per block, before the repeat loop. The
# error_log cursor, in contrast, advances per run, so the second run only sees
# what was logged after the first one read the file -- with the sleep in
# "--- init" that window is a few hundred milliseconds and holds no check at
# all. "--- wait" sleeps right before each run's error_log assertion instead,
# giving every run a window of its own. Ten seconds fits at least two checks:
# begin_handler polls every check_interval / 2 and starts a check once
# check_interval has passed since the previous one started, so checks land
# 3s to 4.5s apart here.
--- wait: 10
--- request
GET /
--- response_body chomp
still-up
--- error_log eval
# Any count above 1 proves reuse. It cannot be pinned to "requests=2": the
# second run picks up the error log where the first left off, and by then the
# surviving connection is already several checks in. Without the fix every line
# reads requests=1 and nothing here matches.
qr/healthcheck-conn requests=(?!1\b)\d+/
