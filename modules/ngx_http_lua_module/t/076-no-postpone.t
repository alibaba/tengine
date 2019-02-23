# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 1);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: rewrite no postpone on
--- http_config
    rewrite_by_lua_no_postpone on;
--- config
    set $foo '';
    location /t {
        rewrite_by_lua '
            ngx.var.foo = 1
        ';
        if ($foo = 1) {
            echo "foo: $foo";
        }
        echo "no foo: $foo";
    }
--- request
GET /t
--- response_body
foo: 1
--- no_error_log
[error]



=== TEST 2: rewrite no postpone explicitly off
--- http_config
    rewrite_by_lua_no_postpone off;
--- config
    set $foo '';
    location /t {
        rewrite_by_lua '
            ngx.var.foo = 1
        ';
        if ($foo = 1) {
            echo "foo: $foo";
        }
        echo "no foo: $foo";
    }
--- request
GET /t
--- response_body
no foo: 1
--- no_error_log
[error]



=== TEST 3: rewrite no postpone off by default
--- config
    set $foo '';
    location /t {
        rewrite_by_lua '
            ngx.var.foo = 1
        ';
        if ($foo = 1) {
            echo "foo: $foo";
        }
        echo "no foo: $foo";
    }
--- request
GET /t
--- response_body
no foo: 1
--- no_error_log
[error]



=== TEST 4: access no postpone on
--- http_config
    access_by_lua_no_postpone on;
--- config
    location /t {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo")
            ngx.say("hi")
        ';
        content_by_lua 'return';
        deny all;
    }
--- request
GET /t
--- response_headers
Location: http://www.taobao.com/foo
--- response_body_like: 302 Found
--- error_code: 302
--- no_error_log
[error]



=== TEST 5: access no postpone explicitly off
--- http_config
    access_by_lua_no_postpone off;
--- config
    location /t {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo")
            ngx.say("hi")
        ';
        content_by_lua 'return';
        deny all;
    }
--- request
GET /t
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule



=== TEST 6: access no postpone off by default
--- config
    location /t {
        access_by_lua '
            ngx.redirect("http://www.taobao.com/foo")
            ngx.say("hi")
        ';
        content_by_lua 'return';
        deny all;
    }
--- request
GET /t
--- response_body_like: 403 Forbidden
--- error_code: 403
--- error_log
access forbidden by rule
