# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 3);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: rewrite I/O with content I/O
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc {
        set $memc_key $echo_request_uri;
        set $memc_exptime 600;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /lua {
        rewrite_by_lua '
            ngx.location.capture("/flush");

            local res = ngx.location.capture("/memc");
            print("rewrite GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello" });
            print("rewrite PUT: " .. res.status);

            res = ngx.location.capture("/memc");
            print("rewrite cached: " .. res.body);
        ';

        content_by_lua '
            ngx.location.capture("/flush");

            local res = ngx.location.capture("/memc");
            ngx.say("content GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello" });
            ngx.say("content PUT: " .. res.status);

            res = ngx.location.capture("/memc");
            ngx.say("content cached: " .. res.body);
        ';
    }
--- request
GET /lua
--- response_body
content GET: 404
content PUT: 201
content cached: hello
--- grep_error_log eval: qr/rewrite .+?(?= while )/
--- grep_error_log_out
rewrite GET: 404
rewrite PUT: 201
rewrite cached: hello

--- log_level: info
--- no_error_log
[error]
[alert]



=== TEST 2: share data via nginx variables
--- config
    location /foo {
        set $foo '';
        rewrite_by_lua '
            ngx.var.foo = 32
        ';

        content_by_lua '
            ngx.say(tonumber(ngx.var.foo) * 2)
        ';
    }
--- request
    GET /foo
--- response_body
64



=== TEST 3: share the request body (need request body explicitly off)
--- config
    location /echo_body {
        lua_need_request_body off;
        set $res '';
        rewrite_by_lua '
            ngx.var.res = ngx.var.request_body or "nil"
        ';
        content_by_lua '
            ngx.say(ngx.var.res or "nil")
            ngx.say(ngx.var.request_body or "nil")
        ';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body
nil
nil



=== TEST 4: share the request body (need request body off by default)
--- config
    location /echo_body {
        #lua_need_request_body off;
        set $res '';
        rewrite_by_lua '
            ngx.var.res = ngx.var.request_body or "nil"
        ';
        content_by_lua '
            ngx.say(ngx.var.res or "nil")
            ngx.say(ngx.var.request_body or "nil")
        ';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body
nil
nil



=== TEST 5: share the request body (need request body on)
--- config
    location /echo_body {
        lua_need_request_body on;
        set $res '';
        rewrite_by_lua '
            ngx.var.res = ngx.var.request_body or "nil"
        ';
        content_by_lua '
            ngx.say(ngx.var.res or "nil")
            ngx.say(ngx.var.request_body or "nil")
        ';
    }
--- request eval
"POST /echo_body
hello\x00\x01\x02
world\x03\x04\xff"
--- response_body eval
"hello\x00\x01\x02
world\x03\x04\xff
hello\x00\x01\x02
world\x03\x04\xff
"
