# vi:filetype=perl
# Copyright (C) 2019 Alibaba Group Holding Limited.
#
use lib 'lib';
use Test::Nginx::LWP;
use Test::Nginx::Socket;

plan tests => repeat_each(1) * 2 * blocks();

no_root_location();

run_tests();

__DATA__



=== TEST 1: the websocket check
--- http_config
    upstream testwebsocket{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        #It's a standard websocket request.
        check_http_send "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==\r\n\r\n";
        check_http_expect_alive http_1xx;
    }

    server {
        listen 1971;

        location / {
            #For health checker's response.
            if ($http_upgrade = "websocket") {
                return 101;
            }
            return 200 "websocket service";
        }
    }

    server {
        listen 1970;

        location / {
            return 200 "http service";
        }
    }

--- config
    location / {
        proxy_pass http://testwebsocket;
    }

--- request
GET /
--- response_body_like: ^.*websocket.*$


=== TEST 2: the http check
--- http_config
    upstream testhttp{
        server 127.0.0.1:1970;
        server 127.0.0.1:1971;

        check interval=3000 rise=1 fall=1 timeout=1000 type=http;
        check_http_send "GET /hc HTTP/1.1\r\nHost: localhost\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    server {
        listen 1971;

        location / {
            return 101;
        }
    }

    server {
        listen 1970;

        location / {
            return 200 "http service";
        }
    }

--- config
    location / {
        proxy_pass http://testhttp;
    }

--- request
GET /http
--- response_body_like: ^.*http.*$
