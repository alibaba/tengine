# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: bind to empty
--- no_http2
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
    }
--- config
    set $proxy_local_addr "";
    proxy_bind $proxy_local_addr;

    location = /t {
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }

--- request
    GET /t
--- response_body
ok
--- no_error_log
[cirt]



=== TEST 2: bind to 127.0.0.1
--- no_http2
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
    }
--- config
    set $proxy_local_addr "";
    proxy_bind $proxy_local_addr;

    location = /t {
        access_by_lua_block {
            ngx.var.proxy_local_addr="127.0.0.1"
        }
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }

--- request
    GET /t
--- response_body
ok
--- no_error_log
[cirt]



=== TEST 3: bind to 127.0.0.10
--- no_http2
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
    }
--- config
    set $proxy_local_addr "";
    proxy_bind $proxy_local_addr;

    location = /t {
        access_by_lua_block {
            ngx.var.proxy_local_addr="127.0.0.10"
        }
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }

--- request
    GET /t
--- response_body
ok
--- no_error_log
[cirt]



=== TEST 4: bind to not exist addr 100.100.100.100
--- no_http2
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    upstream backend {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
    }
--- config
    set $proxy_local_addr "";
    proxy_bind $proxy_local_addr;

    location = /t {
        access_by_lua_block {
            ngx.var.proxy_local_addr="100.100.100.100"
        }
        proxy_pass http://backend/back;
    }

    location = /back {
        echo ok;
    }

--- request
    GET /t
--- response_body_like chomp
500 Internal Server Error
--- error_code: 500
--- error_log
bind(100.100.100.100) failed (99: Cannot assign requested address)
