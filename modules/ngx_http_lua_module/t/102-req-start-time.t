# -*- mode: conf -*-
# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: start time
--- config
    location = /start {
        content_by_lua 'ngx.say(ngx.req.start_time())';
    }
--- request
GET /start
--- response_body_like: ^\d{10,}(\.\d+)?$
--- no_error_log
[error]



=== TEST 2: start time in set_by_lua
--- config
    location = /start {
        set_by_lua $a 'return ngx.req.start_time()';
        echo $a;
    }
--- request
GET /start
--- response_body_like: ^\d{10,}(\.\d+)?$
--- no_error_log
[error]



=== TEST 3: request time
--- config
    location = /req_time {
        content_by_lua '
            ngx.sleep(0.1)

            local req_time = ngx.now() - ngx.req.start_time()

            ngx.say(req_time)
            ngx.say(ngx.req.start_time() < ngx.now())
        ';
    }
--- request
GET /req_time
--- response_body_like chop
^(?:0\.[12]|0\.099)\d*
true$
--- no_error_log
[error]



=== TEST 4: request time update
--- config
    location = /req_time {
            content_by_lua '
               ngx.sleep(0.1)

               local req_time = ngx.now() - ngx.req.start_time()

               ngx.sleep(0.1)

               ngx.update_time()

               local req_time_updated = ngx.now() - ngx.req.start_time()

               ngx.say(req_time)
               ngx.say(req_time_updated)
               ngx.say(req_time_updated > req_time)
            ';
    }
--- request
GET /req_time
--- response_body_like chomp
^(?:0\.[12]|0\.099)\d*
0\.\d+
true$
--- no_error_log
[error]



=== TEST 5: init_by_lua
--- http_config
    init_by_lua '
        time = ngx.req.start_time()
    ';
--- config
    location = /t {
        content_by_lua '
            ngx.say(time)
        ';
    }
--- request
    GET /t
--- response_body
--- no_error_log
[error]
--- SKIP
