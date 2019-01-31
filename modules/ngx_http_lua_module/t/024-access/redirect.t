# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => blocks() * repeat_each() * 3;

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: default 302
--- config
    location /read {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo");
            ngx.say("hi")
        ';
        content_by_lua 'return';
    }
--- request
GET /read
--- response_headers
Location: http://www.taobao.com/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 2: explicit 302
--- config
    location /read {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo", ngx.HTTP_MOVED_TEMPORARILY);
            ngx.say("hi")
        ';
        content_by_lua 'return';
    }
--- request
GET /read
--- response_headers
Location: http://www.taobao.com/foo
--- response_body_like: 302 Found
--- error_code: 302



=== TEST 3: explicit 301
--- config
    location /read {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo", ngx.HTTP_MOVED_PERMANENTLY);
            ngx.say("hi")
        ';
        content_by_lua 'return';
    }
--- request
GET /read
--- response_headers
Location: http://www.taobao.com/foo
--- response_body_like: 301 Moved Permanently
--- error_code: 301



=== TEST 4: bad rc
--- config
    location /read {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo", 404);
            ngx.say("hi")
        ';
        content_by_lua 'return';
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
        access_by_lua '
            ngx.redirect()
            ngx.say("hi")
        ';
        content_by_lua 'return';
    }
--- request
GET /read
--- response_headers
!Location
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: relative uri
--- config
    location /read {
        access_by_lua '
            ngx.redirect("/foo")
            ngx.say("hi")
        ';
        content_by_lua 'return';
    }
--- request
GET /read
--- raw_response_headers_like: Location: /foo\r\n
--- response_body_like: 302 Found
--- error_code: 302
