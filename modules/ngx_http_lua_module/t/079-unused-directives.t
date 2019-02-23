# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('debug');

repeat_each(2);

plan tests => repeat_each() * 110;

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



=== TEST 11: header_filter_by_lua with multiple http blocks (github issue #294)
This test case won't run with nginx 1.9.3+ since duplicate http {} blocks
have been prohibited since then.
--- SKIP
--- config
    location = /t {
        echo ok;
        header_filter_by_lua '
            ngx.status = 201
            ngx.header.Foo = "foo"
        ';

    }
--- post_main_config
    http {
    }
--- request
GET /t
--- response_headers
Foo: foo
--- response_body
ok
--- error_code: 201
--- no_error_log
[error]



=== TEST 12: body_filter_by_lua in multiple http blocks (github issue #294)
This test case won't run with nginx 1.9.3+ since duplicate http {} blocks
have been prohibited since then.
--- SKIP
--- config
    location = /t {
        echo -n ok;
        body_filter_by_lua '
            if ngx.arg[2] then
                ngx.arg[1] = ngx.arg[1] .. "ay\\n"
            end
        ';

    }
--- post_main_config
    http {
    }
--- request
GET /t
--- response_body
okay
--- no_error_log
[error]



=== TEST 13: capture filter with multiple http blocks (github issue #294)
This test case won't run with nginx 1.9.3+ since duplicate http {} blocks
have been prohibited since then.
--- SKIP
--- config
    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.say("sub: ", res.body)
        ';
    }

    location = /sub {
        echo -n sub;
    }
--- post_main_config
    http {
    }
--- request
GET /t
--- response_body
sub: sub
--- no_error_log
[error]
