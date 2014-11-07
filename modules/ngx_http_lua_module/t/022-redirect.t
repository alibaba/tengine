# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 1);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: default 302
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo");
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 2: explicit 302
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_MOVED_TEMPORARILY);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 3: explicit 301
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", ngx.HTTP_MOVED_PERMANENTLY);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body_like: 301 Moved Permanently
--- error_code: 301



=== TEST 4: bad rc
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo", 404);
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
!Location
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 5: no args
--- config
    location /read {
        content_by_lua '
            ngx.redirect()
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
!Location
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: relative uri
--- config
    location /echo {
        echo hello, world;
    }
    location /proxy {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /read {
        content_by_lua '
            ngx.location.capture("/proxy")
            ngx.redirect("/echo")
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- raw_response_headers_like: Location: http://localhost(?::\d+)?/echo\r\n
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 7: default 302 (with uri args)
--- config
    location /read {
        content_by_lua '
            ngx.redirect("http://agentzh.org/foo?bar=3");
            ngx.say("hi")
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo?bar=3
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 8: location.capture + ngx.redirect
--- config
    location /echo {
        echo hello, world;
    }
    location /proxy {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/echo;
    }
    location /read {
        content_by_lua '
            ngx.location.capture("/proxy")
            ngx.location.capture("/proxy")
            ngx.redirect("/echo")
            ngx.exit(403)
        ';
    }
--- pipelined_requests eval
["GET /read/1", "GET /read/2"]
--- error_code eval
[302, 302]
--- response_body eval
[qr/302 Found/, qr/302 Found/]

