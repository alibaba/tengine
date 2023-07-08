# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(10140);
#workers(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3) + 1;

no_long_string();
#no_diff();

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config || '';
    $http_config .= <<'_EOC_';
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: timer + shutdown error log
--- config
    location /test {
        content_by_lua_block {
            local function test(pre)

                local semaphore = require "ngx.semaphore"
                local sem = semaphore.new()

                local function sem_wait()

                    local ok, err = sem:wait(10)
                    if not ok then
                        ngx.log(ngx.ERR, "err: ", err)
                    else
                        ngx.log(ngx.ERR, "wait success")
                    end
                end

                while not ngx.worker.exiting() do
                    local co = ngx.thread.spawn(sem_wait)
                    ngx.thread.wait(co)
                end
            end

            local ok, err = ngx.timer.at(0, test)
            ngx.log(ngx.ERR, "hello, world")
            ngx.say("time: ", ok)
        }
    }
--- request
GET /test
--- response_body
time: 1
--- grep_error_log eval: qr/hello, world|semaphore gc wait queue is not empty/
--- grep_error_log_out
hello, world
--- shutdown_error_log
--- no_shutdown_error_log
semaphore gc wait queue is not empty



=== TEST 2: timer + shutdown error log (lua code cache off)
FIXME: this test case leaks memory.
--- http_config
    lua_code_cache off;
--- config
    location /test {
        content_by_lua_block {
            local function test(pre)

                local semaphore = require "ngx.semaphore"
                local sem = semaphore.new()

                local function sem_wait()

                    local ok, err = sem:wait(10)
                    if not ok then
                        ngx.log(ngx.ERR, "err: ", err)
                    else
                        ngx.log(ngx.ERR, "wait success")
                    end
                end

                while not ngx.worker.exiting() do
                    local co = ngx.thread.spawn(sem_wait)
                    ngx.thread.wait(co)
                end
            end

            local ok, err = ngx.timer.at(0, test)
            ngx.log(ngx.ERR, "hello, world")
            ngx.say("time: ", ok)
        }
    }
--- request
GET /test
--- response_body
time: 1
--- grep_error_log eval: qr/hello, world|semaphore gc wait queue is not empty/
--- grep_error_log_out
hello, world
--- shutdown_error_log
--- no_shutdown_error_log
semaphore gc wait queue is not empty
--- SKIP



=== TEST 3: exit before post_handler was called
If gc is called before the ngx_http_lua_sema_handler and free the sema memory
ngx_http_lua_sema_handler would use the freed memory.
--- config
    location /up {
        content_by_lua_block {
            local semaphore = require "ngx.semaphore"
            local sem = semaphore.new()

            local function sem_wait()
                ngx.log(ngx.ERR, "ngx.sem wait start")
                local ok, err = sem:wait(10)
                if not ok then
                    ngx.log(ngx.ERR, "ngx.sem wait err: ", err)
                else
                    ngx.log(ngx.ERR, "ngx.sem wait success")
                end
            end
            local co = ngx.thread.spawn(sem_wait)
            ngx.log(ngx.ERR, "ngx.sem post start")
            sem:post()
            ngx.log(ngx.ERR, "ngx.sem post end")
            ngx.say("hello")
            ngx.exit(200)
            ngx.say("not reach here")
        }
    }

    location /t {
        content_by_lua_block {
            local res = ngx.location.capture("/up")
            collectgarbage()
            ngx.print(res.body)
        }
    }

--- request
GET /t
--- response_body
hello
--- grep_error_log eval: qr/(ngx.sem .*?,|http close request|semaphore handler: wait queue: empty, resource count: 1|in lua gc, semaphore)/
--- grep_error_log_out
ngx.sem wait start,
ngx.sem post start,
ngx.sem post end,
in lua gc, semaphore
http close request
