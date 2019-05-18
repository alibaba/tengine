# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(10);

plan tests => repeat_each() * (blocks() * 2 + 4);

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#log_level 'warn';
no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
    }
    location /a {
        echo -n a;
    }
    location /b {
        echo -n b;
    }
--- request
    GET /foo
--- response_body
res1.status = 200
res1.body = a
res2.status = 200
res2.body = b



=== TEST 2: 4 concurrent requests
--- config
    location /foo {
        content_by_lua '
            local res1, res2, res3, res4 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
                { "/c" },
                { "/d" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)

            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)

            ngx.say("res3.status = " .. res3.status)
            ngx.say("res3.body = " .. res3.body)

            ngx.say("res4.status = " .. res4.status)
            ngx.say("res4.body = " .. res4.body)
        ';
    }
    location ~ '^/([a-d])$' {
        echo -n $1;
    }
--- request
    GET /foo
--- response_body
res1.status = 200
res1.body = a
res2.status = 200
res2.body = b
res3.status = 200
res3.body = c
res4.status = 200
res4.body = d



=== TEST 3: capture multi in series
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)

            res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("2 res1.status = " .. res1.status)
            ngx.say("2 res1.body = " .. res1.body)
            ngx.say("2 res2.status = " .. res2.status)
            ngx.say("2 res2.body = " .. res2.body)

        ';
    }
    location /a {
        echo -n a;
    }
    location /b {
        echo -n b;
    }
--- request
    GET /foo
--- response_body
res1.status = 200
res1.body = a
res2.status = 200
res2.body = b
2 res1.status = 200
2 res1.body = a
2 res2.status = 200
2 res2.body = b



=== TEST 4: capture multi in subrequest
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }

            local n = ngx.var.arg_n

            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo?n=1")
            ngx.say("top res.status = " .. res.status)
            ngx.say("top res.body = [" .. res.body .. "]")
        ';
    }

    location /a {
        echo -n a;
    }

    location /b {
        echo -n b;
    }
--- request
    GET /main
--- response_body
top res.status = 200
top res.body = [1 res1.status = 200
1 res1.body = a
1 res2.status = 200
1 res2.body = b
]



=== TEST 5: capture multi in parallel
--- config
    location ~ '^/(foo|bar)$' {
        set $tag $1;
        content_by_lua '
            local res1, res2
            if ngx.var.tag == "foo" then
                res1, res2 = ngx.location.capture_multi{
                    { "/a" },
                    { "/b" },
                }
            else
                res1, res2 = ngx.location.capture_multi{
                    { "/c" },
                    { "/d" },
                }
            end

            local n = ngx.var.arg_n

            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }

    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }

            ngx.say("top res1.status = " .. res1.status)
            ngx.say("top res1.body = [" .. res1.body .. "]")
            ngx.say("top res2.status = " .. res2.status)
            ngx.say("top res2.body = [" .. res2.body .. "]")
        ';
    }

    location ~ '^/([abcd])$' {
        echo -n $1;
    }
--- request
    GET /main
--- response_body
top res1.status = 200
top res1.body = [1 res1.status = 200
1 res1.body = a
1 res2.status = 200
1 res2.body = b
]
top res2.status = 200
top res2.body = [2 res1.status = 200
2 res1.body = c
2 res2.status = 200
2 res2.body = d
]



=== TEST 6: memc sanity
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
    }
    location ~ '^/[ab]$' {
        set $memc_key $uri;
        set $memc_value hello;
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body eval
"res1.status = 201
res1.body = STORED\r

res2.status = 201
res2.body = STORED\r

"



=== TEST 7: memc muti + multi
--- config
    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = [" .. res1.body .. "]")
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = [" .. res2.body .. "]")
        ';
    }
    location ~ '^/(foo|bar)$' {
        set $tag $1;
        content_by_lua '
            local res1, res2
            if ngx.var.tag == "foo" then
                res1, res2 = ngx.location.capture_multi{
                    { "/a" },
                    { "/b" },
                }
            else
                res1, res2 = ngx.location.capture_multi{
                    { "/c" },
                    { "/d" },
                }
            end
            print("args: " .. ngx.var.args)
            local n = ngx.var.arg_n
            ngx.say(n .. " res1.status = " .. res1.status)
            ngx.say(n .. " res1.body = " .. res1.body)
            ngx.say(n .. " res2.status = " .. res2.status)
            ngx.say(n .. " res2.body = " .. res2.body)
        ';
    }
    location ~ '^/[abcd]$' {
        set $memc_key $uri;
        set $memc_value hello;
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /main
--- response_body eval
"res1.status = 200
res1.body = [1 res1.status = 201
1 res1.body = STORED\r

1 res2.status = 201
1 res2.body = STORED\r

]
res2.status = 200
res2.body = [2 res1.status = 201
2 res1.body = STORED\r

2 res2.status = 201
2 res2.body = STORED\r

]
"



=== TEST 8: memc 4 concurrent requests
--- config
    location /foo {
        content_by_lua '
            local res1, res2, res3, res4 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
                { "/c" },
                { "/d" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)

            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)

            ngx.say("res3.status = " .. res3.status)
            ngx.say("res3.body = " .. res3.body)

            ngx.say("res4.status = " .. res4.status)
            ngx.say("res4.body = " .. res4.body)
        ';
    }
    location ~ '^/[a-d]$' {
        set $memc_key $uri;
        set $memc_value hello;
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }
--- request
    GET /foo
--- response_body eval
"res1.status = 201
res1.body = STORED\r

res2.status = 201
res2.body = STORED\r

res3.status = 201
res3.body = STORED\r

res4.status = 201
res4.body = STORED\r

"



=== TEST 9: capture multi in series (more complex)
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            local res3, res4 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            res3, res4 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }

            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
            ngx.say("res3.status = " .. res3.status)
            ngx.say("res3.body = " .. res3.body)
            ngx.say("res4.status = " .. res4.status)
            ngx.say("res4.body = " .. res4.body)

        ';
    }
    location /a {
        echo -n a;
    }
    location /b {
        echo -n b;
    }
    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo" },
                { "/foo" },
            }
            local res3, res4 = ngx.location.capture_multi{
                { "/foo" },
                { "/foo" },
            }
            ngx.print(res1.body)
            ngx.print(res2.body)
            ngx.print(res3.body)
            ngx.print(res4.body)
        ';
    }
--- request
    GET /main
--- response_body eval
"res1.status = 200
res1.body = a
res2.status = 200
res2.body = b
res3.status = 200
res3.body = a
res4.status = 200
res4.body = b
" x 4



=== TEST 10: capture multi in series (more complex, using memc)
--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            local res3, res4 = ngx.location.capture_multi{
                { "/c" },
                { "/d" },
            }
            res3, res4 = ngx.location.capture_multi{
                { "/e" },
                { "/f" },
            }

            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
            ngx.say("res3.status = " .. res3.status)
            ngx.say("res3.body = " .. res3.body)
            ngx.say("res4.status = " .. res4.status)
            ngx.say("res4.body = " .. res4.body)
        ';
    }

    location /memc {
        set $memc_key $arg_val;
        set $memc_value $arg_val;
        set $memc_cmd $arg_cmd;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location ~ '^/([a-f])$' {
        set $tag $1;
        content_by_lua '
            ngx.location.capture("/memc?cmd=set&val=" .. ngx.var.tag)
            local res = ngx.location.capture("/memc?cmd=get&val=" .. ngx.var.tag)
            ngx.print(res.body)
        ';
    }

    location /main {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo" },
                { "/foo" },
            }
            local res3, res4 = ngx.location.capture_multi{
                { "/foo" },
                { "/foo" },
            }
            ngx.print(res1.body)
            ngx.print(res2.body)
            ngx.print(res3.body)
            ngx.print(res4.body)
        ';
    }
--- request
    GET /main
--- response_body2
--- response_body eval
"res1.status = 200
res1.body = a
res2.status = 200
res2.body = b
res3.status = 200
res3.body = e
res4.status = 200
res4.body = f
" x 4
--- no_error_log eval
["[error]", "[alert]"]
--- timeout: 10



=== TEST 11: a mixture of rewrite, access, content phases
--- config
    location /main {
        rewrite_by_lua '
            local res = ngx.location.capture("/a")
            print("rewrite a: " .. res.body)

            res = ngx.location.capture("/b")
            print("rewrite b: " .. res.body)

            res = ngx.location.capture("/c")
            print("rewrite c: " .. res.body)
        ';

        access_by_lua '
            local res = ngx.location.capture("/A")
            print("access A: " .. res.body)

            res = ngx.location.capture("/B")
            print("access B: " .. res.body)
        ';

        content_by_lua '
            local res = ngx.location.capture("/d")
            ngx.say("content d: " .. res.body)

            res = ngx.location.capture("/e")
            ngx.say("content e: " .. res.body)

            res = ngx.location.capture("/f")
            ngx.say("content f: " .. res.body)
        ';
    }

    location /memc {
        set $memc_key $arg_val;
        set $memc_value $arg_val;
        set $memc_cmd $arg_cmd;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location ~ '^/([A-F])$' {
        echo -n $1;
    }

    location ~ '^/([a-f])$' {
        set $tag $1;
        content_by_lua '
            ngx.location.capture("/memc?cmd=set&val=" .. ngx.var.tag)
            local res = ngx.location.capture("/memc?cmd=get&val=" .. ngx.var.tag)
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body
content d: d
content e: e
content f: f

--- log_level: info
--- grep_error_log eval: qr/rewrite .+?(?= while )|access .+?(?=,)/
--- grep_error_log_out
rewrite a: a
rewrite b: b
rewrite c: c
access A: A
access B: B



=== TEST 12: a mixture of rewrite, access, content phases
--- config
    location /main {
        rewrite_by_lua '
            local a, b, c = ngx.location.capture_multi{
                {"/a"}, {"/b"}, {"/c"},
            }
            print("rewrite a: " .. a.body)
            print("rewrite b: " .. b.body)
            print("rewrite c: " .. c.body)
        ';

        access_by_lua '
            local A, B = ngx.location.capture_multi{
                {"/A"}, {"/B"},
            }
            print("access A: " .. A.body)
            print("access B: " .. B.body)
        ';

        content_by_lua '
            local d, e, f = ngx.location.capture_multi{
                {"/d"}, {"/e"}, {"/f"},
            }
            ngx.say("content d: " .. d.body)
            ngx.say("content e: " .. e.body)
            ngx.say("content f: " .. f.body)
        ';
    }

    location /memc {
        set $memc_key $arg_val;
        set $memc_value $arg_val;
        set $memc_cmd $arg_cmd;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location ~ '^/([A-F])$' {
        echo -n $1;
    }

    location ~ '^/([a-f])$' {
        set $tag $1;
        content_by_lua '
            ngx.location.capture("/memc?cmd=set&val=" .. ngx.var.tag)
            local res = ngx.location.capture("/memc?cmd=get&val=" .. ngx.var.tag)
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- stap2
global delta = "  "

M(http-subrequest-start) {
    r = $arg1
    n = ngx_http_subreq_depth(r)
    pr = ngx_http_req_parent(r)
    printf("%sbegin %s -> %s (%d)\n", ngx_indent(n, delta),
        ngx_http_req_uri(pr),
        ngx_http_req_uri(r),
        n)
}

F(ngx_http_lua_run_thread) {
    r = $r
    uri = ngx_http_req_uri(r)
    if (uri == "/main") {
        printf("run thread %s: %d\n", uri, $nret)
        #print_ubacktrace()
    }
}

M(http-lua-info) {
    uri = ngx_http_req_uri($r)
    #if (uri == "/main") {
    printf("XXX info: %s: %s", uri, user_string($arg1))
    #}
}

F(ngx_http_lua_post_subrequest) {
    r = $r
    n = ngx_http_subreq_depth(r)
    pr = ngx_http_req_parent(r)

    printf("%send %s -> %s (%d)\n", ngx_indent(n, delta),
        ngx_http_req_uri(r),
        ngx_http_req_uri(pr),
        n)
}

F(ngx_http_lua_handle_subreq_responses) {
    r = $r
    n = ngx_http_subreq_depth(r)
    printf("%shandle res %s (%d)\n", ngx_indent(n, delta), ngx_http_req_uri(r), n)
}

--- response_body
content d: d
content e: e
content f: f
--- log_level: info
--- grep_error_log eval: qr/rewrite .+?(?= while )|access .+?(?=,)/
--- grep_error_log_out
rewrite a: a
rewrite b: b
rewrite c: c
access A: A
access B: B



=== TEST 13: proxy_cache_lock in subrequests
--- http_config
proxy_cache_lock on;
proxy_cache_lock_timeout 100ms;
proxy_connect_timeout 300ms;

proxy_cache_path conf/cache levels=1:2 keys_zone=STATIC:10m inactive=10m max_size=1m;

--- config
    location /foo {
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/proxy" },
                { "/proxy" },
                { "/proxy" },
                { "/proxy" },
            }
            ngx.say("ok")
        ';
    }

    location = /proxy {
            proxy_cache STATIC;
            proxy_pass http://127.0.0.2:12345;
            proxy_cache_key $proxy_host$uri$args;
            proxy_cache_valid any 1s;
            #proxy_http_version 1.1;
    }
--- request
    GET /foo
--- response_body
ok
