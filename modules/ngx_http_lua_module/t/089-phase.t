# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 1);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: get_phase in init_by_lua
--- http_config
    init_by_lua 'phase = ngx.get_phase()';
--- config
    location /lua {
        content_by_lua '
            ngx.say(phase)
        ';
    }
--- request
GET /lua
--- response_body
init



=== TEST 2: get_phase in set_by_lua
--- config
    set_by_lua $phase 'return ngx.get_phase()';
    location /lua {
        content_by_lua '
            ngx.say(ngx.var.phase)
        ';
    }
--- request
GET /lua
--- response_body
set



=== TEST 3: get_phase in rewrite_by_lua
--- config
    location /lua {
        rewrite_by_lua '
            ngx.say(ngx.get_phase())
            ngx.exit(200)
        ';
    }
--- request
GET /lua
--- response_body
rewrite



=== TEST 4: get_phase in access_by_lua
--- config
    location /lua {
        access_by_lua '
            ngx.say(ngx.get_phase())
            ngx.exit(200)
        ';
    }
--- request
GET /lua
--- response_body
access



=== TEST 5: get_phase in content_by_lua
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.get_phase())
        ';
    }
--- request
GET /lua
--- response_body
content



=== TEST 6: get_phase in header_filter_by_lua
--- config
    location /lua {
        echo "OK";
        header_filter_by_lua '
            ngx.header.Phase = ngx.get_phase()
        ';
    }
--- request
GET /lua
--- response_header
Phase: header_filter



=== TEST 7: get_phase in body_filter_by_lua
--- config
    location /lua {
        content_by_lua '
            ngx.exit(200)
        ';
        body_filter_by_lua '
            ngx.arg[1] = ngx.get_phase()
        ';
    }
--- request
GET /lua
--- response_body chop
body_filter



=== TEST 8: get_phase in log_by_lua
--- config
    location /lua {
        echo "OK";
        log_by_lua '
            ngx.log(ngx.ERR, ngx.get_phase())
        ';
    }
--- request
GET /lua
--- error_log
log



=== TEST 9: get_phase in ngx.timer callback
--- config
    location /lua {
        echo "OK";
        log_by_lua '
            local function f()
                ngx.log(ngx.WARN, "current phase: ", ngx.get_phase())
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to add timer: ", err)
            end
        ';
    }
--- request
GET /lua
--- no_error_log
[error]
--- error_log
current phase: timer



=== TEST 10: get_phase in init_worker_by_lua
--- http_config
    init_worker_by_lua 'phase = ngx.get_phase()';
--- config
    location /lua {
        content_by_lua '
            ngx.say(phase)
        ';
    }
--- request
GET /lua
--- response_body
init_worker
--- no_error_log
[error]
