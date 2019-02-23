# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: lua code cache on
--- http_config
    lua_code_cache on;
--- config
    location = /cache_on {
        content_by_lua_block {
            local delayed_load = require("ngx.delayed_load")
            ngx.say(type(delayed_load.get_function))
        }
    }
--- request
GET /cache_on
--- response_body
function
--- no_error_log
[error]



=== TEST 2: lua code cache off
--- http_config
    lua_code_cache off;
--- config
    location = /cache_off {
        content_by_lua_block {
            local delayed_load = require("ngx.delayed_load")
            ngx.say(type(delayed_load.get_function))
        }
    }
--- request
GET /cache_off
--- response_body
function
--- no_error_log
[error]
