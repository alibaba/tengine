# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 - 4);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: content_by_lua + ngx.worker.exiting
--- config
    location /lua {
        content_by_lua '
            ngx.say("worker exiting: ", ngx.worker.exiting())
        ';
    }
--- request
GET /lua
--- response_body
worker exiting: false
--- no_error_log
[error]



=== TEST 2: content_by_lua + ngx.worker.pid
--- config
    location /lua {
        content_by_lua '
            local pid = ngx.worker.pid()
            ngx.say("worker pid: ", pid)
            if pid ~= tonumber(ngx.var.pid) then
                ngx.say("worker pid is wrong.")
            else
                ngx.say("worker pid is correct.")
            end
        ';
    }
--- request
GET /lua
--- response_body_like
worker pid: \d+
worker pid is correct\.
--- no_error_log
[error]



=== TEST 3: init_worker_by_lua + ngx.worker.pid
--- http_config
    init_worker_by_lua '
        my_pid = ngx.worker.pid()
    ';
--- config
    location /lua {
        content_by_lua '
            ngx.say("worker pid: ", my_pid)
            if my_pid ~= tonumber(ngx.var.pid) then
                ngx.say("worker pid is wrong.")
            else
                ngx.say("worker pid is correct.")
            end
        ';
    }
--- request
GET /lua
--- response_body_like
worker pid: \d+
worker pid is correct\.
--- no_error_log
[error]



=== TEST 4: content_by_lua + ngx.worker.pids
--- config
    location /lua {
        content_by_lua '
            local pids = ngx.worker.pids()
            local pid = ngx.worker.pid()
            ngx.say("worker pid: ", pid)
            local count = ngx.worker.count()
            if count ~= #pids then
                ngx.say("worker pids is wrong.")
            end
            for i = 1, count do
                if pids[i] == pid then
                    ngx.say("worker pid is correct.")
                    return
                end
            end
            ngx.say("worker pid is wrong.")
        ';
    }
--- request
GET /lua
--- response_body_like
worker pid: \d+
worker pid is correct\.
--- no_error_log
[error]
