# vi:filetype=perl

# Regression cases for "check ... port=N" combined with unix domain socket
# servers.
#
# A unix domain socket has no port, so port= cannot be applied to it. It used to
# make ngx_http_upstream_check_add_peer() fail, which left the peer's
# check_index at NGX_ERROR; ngx_http_upstream_check_peer_down() fails open on an
# invalid index, so the socket was reported alive forever and the load balancer
# kept selecting it even while the health check itself had marked it down. The
# expected behaviour is that port= is ignored for such a peer and the peer is
# checked on its own address.
#
# Every block sets "proxy_next_upstream off". Without it the retry to the next
# peer masks the bug: the request still ends up with a 200 after one failed
# connection, so the case would pass both before and after the fix.
#
# Blocks whose expectation depends on a peer having been checked at least once
# wait in "--- init" first: the first check only fires after a random delay of
# up to max(interval, 1s), while the framework sends its request roughly 100ms
# after the server starts.

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each(2) * 2 * blocks();

no_root_location();

run_tests();

__DATA__

=== TEST 1: a unix socket peer with port= is checked on its own address, so a dead socket fails over to the backup
--- http_config
    upstream test_unix_down {
        server unix:/tmp/tengine_check_no_such_socket.sock;
        server 127.0.0.1:1980 backup;

        check interval=500 rise=1 fall=1 timeout=1000 type=http default_down=false port=1981;
        check_http_send "GET /health_check HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    # The backup peer is an IP peer, so port= does apply to it: keep 1981
    # healthy or the backup would be marked down too.
    server {
        listen 1981;
        location / {
            return 200 "PROBE\n";
        }
    }

    server {
        listen 1980;
        location / {
            return 200 "BACKUP\n";
        }
    }

--- config
    location / {
        proxy_pass http://test_unix_down;
        proxy_next_upstream off;
    }

--- init: sleep 3;
--- request
GET /
--- response_body_like: BACKUP

=== TEST 2: a unix socket peer with port= is marked up while its socket is healthy
--- http_config
    upstream test_unix_up {
        server unix:/tmp/tengine_check_unix_up.sock;

        check interval=500 rise=1 fall=1 timeout=1000 type=http default_down=false port=1981;
        check_http_send "GET /health_check HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    server {
        listen unix:/tmp/tengine_check_unix_up.sock;
        location / {
            return 200 "UNIX\n";
        }
    }

    server {
        listen 1981;
        location / {
            return 200 "PROBE\n";
        }
    }

--- config
    location / {
        proxy_pass http://test_unix_up;
        proxy_next_upstream off;
    }

--- init: sleep 3;
--- request
GET /
--- response_body_like: UNIX

=== TEST 3: port= still applies to IP peers, so a dead probe port marks a healthy peer down
--- http_config
    upstream test_ip_probe_down {
        # 1980 serves fine, but the check is redirected to 1982 where nothing
        # listens, so the peer must end up down.
        server 127.0.0.1:1980;

        check interval=500 rise=1 fall=1 timeout=1000 type=http default_down=false port=1982;
        check_http_send "GET /health_check HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    server {
        listen 1980;
        location / {
            return 200 "BACKEND\n";
        }
    }

--- config
    location / {
        proxy_pass http://test_ip_probe_down;
        proxy_next_upstream off;
    }

--- init: sleep 3;
--- request
GET /
--- error_code: 502
--- response_body_like: ^.*$
