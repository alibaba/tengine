# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 6);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /read {
        access_by_lua '
            ngx.exec("/hi");
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body
Hello



=== TEST 2: empty uri arg
--- config
    location /read {
        access_by_lua '
            ngx.exec("");
            ngx.say("Hi");
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: no arg
--- config
    location /read {
        access_by_lua '
            ngx.exec();
            ngx.say("Hi");
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: too many args
--- config
    location /read {
        access_by_lua '
            ngx.exec(1, 2, 3, 4);
            ngx.say("Hi");
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 5: null uri
--- config
    location /read {
        access_by_lua '
            ngx.exec(nil)
            ngx.say("Hi")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: user args
--- config
    location /read {
        access_by_lua '
            ngx.exec("/hi", "Yichun Zhang")
            ngx.say("Hi")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello Yichun Zhang



=== TEST 7: args in uri
--- config
    location /read {
        access_by_lua '
            ngx.exec("/hi?agentzh")
            ngx.say("Hi")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello agentzh



=== TEST 8: args in uri and user args
--- config
    location /read {
        access_by_lua '
            ngx.exec("/hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello a=Yichun&b=Zhang



=== TEST 9: args in uri and user args
--- config
    location /read {
        access_by_lua '
            ngx.exec("@hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
    location @hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello 



=== TEST 10: exec after location capture
--- config
    location /test {
        access_by_lua_file 'html/test.lua';
        echo world;
    }

    location /a {
        echo "hello";
    }

    location /b {
        echo "hello";
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('/b')
--- request
    GET /test
--- response_body
hello



=== TEST 11: exec after (named) location capture
--- config
    location /test {
        access_by_lua_file 'html/test.lua';
    }

    location /a {
        echo "hello";
    }

    location @b {
        echo "hello";
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('@b')
--- request
    GET /test
--- response_body
hello



=== TEST 12: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location /p{
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location /lua {
        access_by_lua '
            ngx.exec("/p")
        ';
    }
--- request
    GET /lua
--- response_body
hello
--- timeout: 3



=== TEST 13: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location (named location)
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location @p {
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location /lua {
        access_by_lua '
            ngx.exec("@p")
        ';
    }
--- request
    GET /lua
--- response_body
hello



=== TEST 14: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location (post subrequest)
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
    }
    location /p{
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location /blah {
        echo blah;
    }
    location /lua {
        access_by_lua '
            ngx.location.capture("/blah")
            ngx.exec("/p")
        ';
    }
--- request
    GET /lua
--- response_body
hello



=== TEST 15: access_by_lua + ngx.exec + subrequest capture
--- config
    location /main {
        access_by_lua '
            local res = ngx.location.capture("/test_loc");
            ngx.print("hello, ", res.body)
        ';
        content_by_lua return;
    }
    location /test_loc {
        rewrite_by_lua '
            ngx.exec("@proxy")
        ';
    }
    location @proxy {
        #echo proxy;
        proxy_pass http://127.0.0.1:$server_port/foo;
    }
    location /foo {
        echo bah;
    }
--- request
    GET /main
--- response_body
hello, bah



=== TEST 16: github issue #905: unsafe uri
--- config
    location /read {
        access_by_lua_block {
            ngx.exec("/hi/../");
        }
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
[
'unsafe URI "/hi/../" was detected',
qr/runtime error: access_by_lua\(nginx.conf:\d+\):2: unsafe uri/,
]



=== TEST 17: pipelined requests
--- config
    location /t {
        access_by_lua_block {
            ngx.exec("@foo")
        }
    }

    location @foo {
        return 200;
    }
--- pipelined_requests eval
["GET /t", "GET /t"]
--- error_code eval
[200, 200]
--- response_body eval
["", ""]
--- no_error_log
[error]
