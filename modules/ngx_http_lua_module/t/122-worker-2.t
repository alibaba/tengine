# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
master_on();
workers(4);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: get worker pids with multiple worker
--- config
    location /lua {
        content_by_lua_block {
            local pids, err = ngx.worker.pids()
            if err ~= nil then
                return
            end
            local pid = ngx.worker.pid()
            ngx.say("worker pid: ", pid)
            local count = ngx.worker.count()
            ngx.say("worker count: ", count)
            ngx.say("worker pids count: ", #pids)
            for i = 1, count do
                if pids[i] == pid then
                    ngx.say("worker pid is correct.")
                    return
                end
            end
        }
    }
--- request
GET /lua
--- response_body_like
worker pid: \d+
worker count: 4
worker pids count: 4
worker pid is correct\.
--- no_error_log
[error]
