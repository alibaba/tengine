# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

#log_level 'warn';
log_level 'debug';

#no_long_string();
#no_diff();
run_tests();

__DATA__

=== TEST 1: lua_use_default_type default on
--- config
    location /lua {
        default_type text/plain;
        content_by_lua '
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- response_headers
Content-Type: text/plain
--- no_error_log
[error]



=== TEST 2: lua_use_default_type explicitly on
--- config
    lua_use_default_type on;
    location /lua {
        default_type text/plain;
        content_by_lua '
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- response_headers
Content-Type: text/plain
--- no_error_log
[error]



=== TEST 3: lua_use_default_type off
--- config
    lua_use_default_type off;
    location /lua {
        default_type text/plain;
        content_by_lua '
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- response_headers
!Content-Type
--- no_error_log
[error]



=== TEST 4: overriding lua_use_default_type off
--- config
    lua_use_default_type off;
    location /lua {
        lua_use_default_type on;
        default_type text/plain;
        content_by_lua '
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- response_headers
Content-Type: text/plain
--- no_error_log
[error]



=== TEST 5: overriding lua_use_default_type on
--- config
    lua_use_default_type on;
    location /lua {
        lua_use_default_type off;
        default_type text/plain;
        content_by_lua '
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- response_headers
!Content-Type
--- no_error_log
[error]

