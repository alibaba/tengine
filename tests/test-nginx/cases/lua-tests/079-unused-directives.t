# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (11 * blocks());

#no_diff();
#no_long_string();
#no_shuffle();

run_tests();

__DATA__

=== TEST 1: rewrite_by_lua unused
--- config
    location /t {
        set_by_lua $i 'return 32';
        #rewrite_by_lua return;
        echo $i;
    }
--- request
GET /t
--- response_body
32
--- no_error_log
lua capture header filter, uri "/t"
lua capture body filter, uri "/t"
lua rewrite handler, uri:"/t"
lua access handler, uri:"/t"
lua content handler, uri:"/t"
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
lua log handler, uri:"/t"
[error]



=== TEST 2: rewrite_by_lua used
--- config
    location /t {
        rewrite_by_lua return;
        echo hello;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua rewrite handler, uri:"/t"
lua capture header filter, uri "/t"
lua capture body filter, uri "/t"
--- no_error_log
lua access handler, uri:"/t"
lua content handler, uri:"/t"
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
lua log handler, uri:"/t"
[error]
--- log_level: debug



=== TEST 3: access_by_lua used
--- config
    location /t {
        access_by_lua return;
        echo hello;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua access handler, uri:"/t" c:1
lua capture body filter, uri "/t"
lua capture header filter, uri "/t"
--- no_error_log
lua rewrite handler, uri:"/t"
lua content handler, uri:"/t"
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
lua log handler, uri:"/t"
[error]



=== TEST 4: content_by_lua used
--- config
    location /t {
        content_by_lua 'ngx.say("hello")';
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua content handler, uri:"/t" c:1
lua capture body filter, uri "/t"
lua capture header filter, uri "/t"
--- no_error_log
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
lua log handler, uri:"/t"
[error]



=== TEST 5: header_filter_by_lua
--- config
    location /t {
        echo hello;
        header_filter_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua header filter for user lua code, uri "/t"
--- no_error_log
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua log handler, uri:"/t"
lua body filter for user lua code, uri "/t"
[error]



=== TEST 6: log_by_lua
--- config
    location /t {
        echo hello;
        log_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua log handler, uri:"/t"
--- no_error_log
lua header filter for user lua code, uri "/t"
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua body filter for user lua code, uri "/t"
[error]



=== TEST 7: body_filter_by_lua
--- config
    location /t {
        echo hello;
        body_filter_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
--- no_error_log
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua log handler, uri:"/t"
[error]



=== TEST 8: header_filter_by_lua_file
--- config
    location /t {
        echo hello;
        header_filter_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
return
--- request
GET /t
--- response_body
hello
--- error_log
lua header filter for user lua code, uri "/t"
--- no_error_log
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua log handler, uri:"/t"
lua body filter for user lua code, uri "/t"
[error]



=== TEST 9: log_by_lua
--- config
    location /t {
        echo hello;
        log_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua log handler, uri:"/t"
--- no_error_log
lua header filter for user lua code, uri "/t"
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua body filter for user lua code, uri "/t"
[error]



=== TEST 10: body_filter_by_lua
--- config
    location /t {
        echo hello;
        body_filter_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- error_log
lua header filter for user lua code, uri "/t"
lua body filter for user lua code, uri "/t"
--- no_error_log
lua capture header filter, uri "/t"
lua content handler, uri:"/t"
lua access handler, uri:"/t"
lua rewrite handler, uri:"/t"
lua capture body filter, uri "/t"
lua log handler, uri:"/t"
[error]

