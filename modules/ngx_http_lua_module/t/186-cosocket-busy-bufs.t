# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket 'no_plan';
use Test::Nginx::Socket::Lua::Stream;

log_level('warn');
repeat_each(2);
run_tests();

__DATA__

=== TEST 1: ngx.say and cosocket
--- stream_server_config
    content_by_lua_block {
        local sock = assert(ngx.req.socket(true))
        sock:settimeout(1000)
        while true do
            local data = sock:receive(5)
            if not data then
                return
            end
            ngx.print(data)
            ngx.flush(true)
        end
    }
--- config
    location /test {
        content_by_lua_block {
            ngx.say("hello")
            --ngx.flush(true)

            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.1", ngx.var.server_port + 1)
            assert(ok)

            local last_duration = 0
            local cnt = 0
            local t1, t2
            local err_cnt = 0
            local ERR_THRESHOLD_MS = 100

            for i = 1,100000 do
                if cnt == 0 then
                    ngx.update_time()
                    t1 = ngx.now()
                end

                cnt = cnt + 1

                local sent = sock:send("hello")
                local data = sock:receive(5)
                assert(data=="hello")

                if cnt == 1000 then
                    cnt = 0
                    ngx.update_time()
                    t2 = ngx.now()
                    local duration = (t2 - t1) * 1000
                    if last_duration > 0 and (duration - last_duration) > ERR_THRESHOLD_MS then
                        if err_cnt >= 3 then
                            ngx.log(ngx.ERR,
                                "more than ", err_cnt, " times, duration larger than ",
                                ERR_THRESHOLD_MS, " ms, ",
                                "last_duration: ", math.floor(duration), " ms")
                            return ngx.exit(500)
                        end
                        err_cnt = err_cnt + 1
                    end
                    last_duration = duration
                end
            end

            sock:close()
            ngx.exit(200)
        }
    }
--- no_error_log
[error]
--- timeout: 30
--- request
GET /test
