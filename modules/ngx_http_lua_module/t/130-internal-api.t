# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * blocks() * 3;

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: req
--- config
    location = /t {
        content_by_lua '
            local ffi = require "ffi"
            local function tonum(ud)
                return tonumber(ffi.cast("uintptr_t", ud))
            end
            ngx.say(string.format("content req=%#x", tonum(exdata())))
        ';
    }
--- request
GET /t

--- response_body_like chop
^content req=0x[a-f0-9]{4,}
$
--- no_error_log
[error]
