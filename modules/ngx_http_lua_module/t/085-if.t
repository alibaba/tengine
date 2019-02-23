# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: set_by_lua (if fails)
--- config
    location /t {
        set $true $arg_a;
        if ($true) {
            set_by_lua $true 'return tonumber(ngx.var["true"]) + 1';
            break;
        }
        set $true "empty";

        echo "[$true]";
    }
--- request
GET /t
--- response_body
[empty]
--- no_error_log
[error]



=== TEST 2: set_by_lua (if true)
--- config
    location /t {
        set $true $arg_a;
        if ($true) {
            set_by_lua $true 'return tonumber(ngx.var["true"]) + 1';
            break;
        }
        set $true "blah";

        echo "[$true]";
    }
--- request
GET /t?a=2
--- response_body
[3]
--- no_error_log
[error]



=== TEST 3: content_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        content_by_lua 'ngx.say("hello world")';
    }
--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]



=== TEST 4: rewrite_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        rewrite_by_lua 'ngx.say("hello world") ngx.exit(200)';
    }
--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]



=== TEST 5: access_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        access_by_lua 'ngx.say("hello world") ngx.exit(200)';
    }
--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]



=== TEST 6: log_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        log_by_lua 'ngx.log(ngx.WARN, "from log by lua")';
        echo hello world;
    }
--- request
GET /t
--- response_body
hello world
--- no_error_log
[error]
--- error_log
from log by lua



=== TEST 7: header_filter_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        header_filter_by_lua 'ngx.header.Foo = "bah"';
        echo hello world;
    }
--- request
GET /t
--- response_body
hello world
--- response_headers
Foo: bah
--- no_error_log
[error]



=== TEST 8: body_filter_by_lua inherited by location if
--- config
    location /t {
        set $true 1;
        if ($true) {
            # nothing
        }

        body_filter_by_lua 'ngx.arg[1] = string.upper(ngx.arg[1])';
        echo hello world;
    }
--- request
GET /t
--- response_body
HELLO WORLD
--- no_error_log
[error]



=== TEST 9: if is evil for ngx_proxy
This test case requires the following patch for the nginx core:
http://mailman.nginx.org/pipermail/nginx-devel/2012-June/002374.html
--- config
    location /proxy-pass-uri {
        proxy_pass http://127.0.0.1:$TEST_NGINX_SERVER_PORT/;

        set $true 1;

        if ($true) {
            # nothing
        }
    }
--- request
GET /proxy-pass-uri
--- response_body_like: It works!
--- no_error_log
[error]
