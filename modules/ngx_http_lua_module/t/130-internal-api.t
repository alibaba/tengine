# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * 3;

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: __ngx_req and __ngx_cycle
--- http_config
    init_by_lua '
        my_cycle = __ngx_cycle
    ';

--- config
    location = /t {
        content_by_lua '
            local ffi = require "ffi"
            local function tonum(ud)
                return tonumber(ffi.cast("uintptr_t", ud))
            end
            ngx.say(string.format("init: cycle=%#x", tonum(my_cycle)))
            ngx.say(string.format("content cycle=%#x", tonum(__ngx_cycle)))
            ngx.say(string.format("content req=%#x", tonum(__ngx_req)))
        ';
    }
--- request
GET /t

--- response_body_like chop
^init: cycle=(0x[a-f0-9]{4,})
content cycle=\1
content req=0x[a-f0-9]{4,}
$
--- no_error_log
[error]

