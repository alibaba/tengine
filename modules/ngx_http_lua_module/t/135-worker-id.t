# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(2);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("worker id: ", ngx.worker.id())
        }
    }
--- request
GET /lua
--- response_body_like chop
^worker id: [0-1]$
--- no_error_log
[error]
--- skip_nginx: 3: <=1.9.0
