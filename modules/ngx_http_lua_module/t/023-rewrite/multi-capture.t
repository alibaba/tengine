# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(10);

plan tests => blocks() * repeat_each() * 2;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /foo {
        rewrite_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
        content_by_lua return;
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
        rewrite_by_lua '
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
        content_by_lua return;
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
        rewrite_by_lua '
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
        content_by_lua return;
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
        rewrite_by_lua '
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
        content_by_lua return;
    }

    location /main {
        rewrite_by_lua '
            local res = ngx.location.capture("/foo?n=1")
            ngx.say("top res.status = " .. res.status)
            ngx.say("top res.body = [" .. res.body .. "]")
        ';
        content_by_lua return;
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
        rewrite_by_lua '
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
        content_by_lua return;
    }

    location /main {
        rewrite_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }

            ngx.say("top res1.status = " .. res1.status)
            ngx.say("top res1.body = [" .. res1.body .. "]")
            ngx.say("top res2.status = " .. res2.status)
            ngx.say("top res2.body = [" .. res2.body .. "]")
        ';
        content_by_lua return;
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
        rewrite_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/a" },
                { "/b" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = " .. res1.body)
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = " .. res2.body)
        ';
        content_by_lua return;
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
        rewrite_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                { "/foo?n=1" },
                { "/bar?n=2" },
            }
            ngx.say("res1.status = " .. res1.status)
            ngx.say("res1.body = [" .. res1.body .. "]")
            ngx.say("res2.status = " .. res2.status)
            ngx.say("res2.body = [" .. res2.body .. "]")
        ';
        content_by_lua return;
    }
    location ~ '^/(foo|bar)$' {
        set $tag $1;
        rewrite_by_lua '
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
        content_by_lua return;
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
        rewrite_by_lua '
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
        content_by_lua return;
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
