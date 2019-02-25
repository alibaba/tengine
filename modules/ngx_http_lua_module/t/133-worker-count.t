# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: content_by_lua
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("workers: ", ngx.worker.count())
        }
    }
--- request
GET /lua
--- response_body
workers: 1
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
workers: 1
--- no_error_log
[error]



=== TEST 3: init_worker_by_lua
--- http_config
    init_worker_by_lua_block {
        init_worker_count = ngx.worker.count()
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("workers: ", init_worker_count)
        }
    }
--- request
GET /lua
--- response_body
workers: 1
--- no_error_log
[error]
