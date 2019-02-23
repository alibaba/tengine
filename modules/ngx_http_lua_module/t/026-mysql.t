# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => blocks() * repeat_each() * 3;

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

no_long_string();

run_tests();

__DATA__

=== TEST 1: when mysql query timed out, kill that query by Lua
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }
--- config
    location = /mysql {
        #internal;
        drizzle_send_query_timeout 100ms;
        #drizzle_send_query_timeout 1s;
        drizzle_query $echo_request_body;
        drizzle_pass backend;

        #error_page 504 /ret/504;
        rds_json on;
        more_set_headers -s 504 "X-Mysql-Tid: $drizzle_thread_id";
    }

    location /lua {
        content_by_lua '
            local sql = "select sleep(5)"
            local res = ngx.location.capture("/mysql",
                { method = ngx.HTTP_POST, body = sql })

            ngx.say("status = " .. res.status)

            local tid = res.header["X-Mysql-Tid"]
            if tid == nil then
                ngx.say("thread id = nil")
                return
            end

            tid = tonumber(tid)
            ngx.say("thread id = " .. tid)

            res = ngx.location.capture("/mysql",
                { method = ngx.HTTP_POST,
                  body = "kill query " .. tid })

            ngx.say("kill status = " .. res.status)
            ngx.say("kill body = " .. res.body)
        ';
    }
--- request
    GET /lua
--- response_body_like
^status = 504
thread id = \d+
kill status = 200
kill body = \{"errcode":0\}$
--- error_log eval
qr{upstream timed out \(\d+: Connection timed out\) while sending query to drizzle upstream}



=== TEST 2: no error pages
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }
--- config
    location @err { echo Hi; }
    error_page 504 = @err;
    location = /mysql {
        #internal;
        drizzle_send_query_timeout 100ms;
        #drizzle_send_query_timeout 1s;
        drizzle_query $echo_request_body;
        drizzle_pass backend;

        no_error_pages;

        rds_json on;
        more_set_headers -s 504 "X-Mysql-Tid: $drizzle_thread_id";
    }

    location /lua {
        content_by_lua '
            local sql = "select sleep(3)"
            local res = ngx.location.capture("/mysql",
                { method = ngx.HTTP_POST, body = sql })

            ngx.say("status = " .. res.status)

            local tid = res.header["X-Mysql-Tid"]
            if tid == nil then
                ngx.say("thread id = nil")
                return
            end

            tid = tonumber(tid)
            ngx.say("thread id = " .. tid)

            res = ngx.location.capture("/mysql",
                { method = ngx.HTTP_POST,
                  body = "kill query " .. tid })

            ngx.say("kill status = " .. res.status)
            ngx.say("kill body = " .. res.body)
        ';
    }
--- request
    GET /lua
--- response_body_like
^status = 504
thread id = \d+
kill status = 200
kill body = \{"errcode":0\}$
--- SKIP
