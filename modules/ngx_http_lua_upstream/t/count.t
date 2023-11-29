# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

$ENV{TEST_NGINX_MY_INIT_CONFIG} = <<_EOC_;
lua_package_path "t/lib/?.lua;;";
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: number of entries in the module table
--- config
    location /t {
        content_by_lua_block {
            local upstream = require "ngx.upstream"
            local c = 0
            for _, _ in pairs(upstream) do
                c = c + 1
            end
            ngx.say("count: ", c)
        }
    }
--- request
    GET /t
--- response_body
count: 6
--- no_error_log
[error]
