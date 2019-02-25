# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');
#no_nginx_manager();

#repeat_each(1);
repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 1);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: basic test passing
--- config
    location /lua {
        lua_need_request_body on;
        client_max_body_size 100k;
        client_body_buffer_size 100k;

        access_by_lua '
            -- check the client IP addr is in our black list
            if ngx.var.remote_addr == "132.5.72.3" then
                ngx.exit(ngx.HTTP_FORBIDDEN)
            end

            -- check if the request body contains bad words
            if ngx.var.request_body and string.match(ngx.var.request_body, "fuck") then
                return ngx.redirect("/terms_of_use.html")
            end

            -- tests passed
        ';

        echo Logged in;
    }
--- request
GET /lua
--- response_body
Logged in



=== TEST 2: bad words in request body
--- config
    location /lua {
        lua_need_request_body on;
        client_max_body_size 100k;
        client_body_buffer_size 100k;

        access_by_lua '
            -- check the client IP addr is in our black list
            if ngx.var.remote_addr == "132.5.72.3" then
                ngx.exit(ngx.HTTP_FORBIDDEN)
            end

            -- check if the request body contains bad words
            if ngx.var.request_body and string.match(ngx.var.request_body, "fuck") then
                return ngx.redirect("/terms_of_use.html")
            end

            -- tests passed
        ';

        echo Logged in;
    }
--- request
POST /lua
He fucks himself!
--- response_body_like: 302 Found
--- response_headers_like
Location: /terms_of_use\.html
--- error_code: 302



=== TEST 3: client IP
--- config
    location /lua {
        lua_need_request_body on;
        client_max_body_size 100k;
        client_body_buffer_size 100k;

        access_by_lua '
            -- check the client IP addr is in our black list
            if ngx.var.remote_addr == "127.0.0.1" then
                ngx.exit(ngx.HTTP_FORBIDDEN)
            end

            -- check if the request body contains bad words
            if ngx.var.request_body and string.match(ngx.var.request_body, "fuck") then
                return ngx.redirect("/terms_of_use.html")
            end

            -- tests passed
        ';

        echo Logged in;
    }
--- request
GET /lua
--- response_body_like: 403 Forbidden
--- error_code: 403
