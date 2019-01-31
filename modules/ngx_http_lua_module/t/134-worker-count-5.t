# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(5);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("worker count: ", ngx.worker.count())
        }
    }
--- request
GET /lua
--- response_body
worker count: 5
--- no_error_log
[error]



=== TEST 2: init_by_lua
--- http_config
    init_by_lua_block {
        package.loaded.count = ngx.worker.count()
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("workers: ", package.loaded.count)
        }
    }
--- request
GET /lua
--- response_body
workers: 5
--- no_error_log
[error]



=== TEST 3: init_by_lua + module (github #681)
--- http_config
    lua_package_path "$TEST_NGINX_SERVER_ROOT/html/?.lua;;";

    init_by_lua_block {
        local blah = require "file"
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("ok")
        }
    }
--- user_files
>>> file.lua
local timer_interval = 1
local time_factor = timer_interval / (ngx.worker.count() * 60)
--- request
GET /lua
--- response_body
ok
--- no_error_log
[error]
