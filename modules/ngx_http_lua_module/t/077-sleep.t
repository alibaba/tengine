# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('debug');

repeat_each(2);

plan tests => repeat_each() * 71;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sleep 0.5 - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.sleep(0.5)
            local now = ngx.now()
            ngx.say(now - before)
        ';
    }
--- request
GET /test
--- response_body_like chop
^0\.(?:4[5-9]\d*|5[0-5]\d*|5)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
lua sleep timer expired: "/test?"



=== TEST 2: sleep a - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.sleep("a")
            local now = ngx.now()
            ngx.say(now - before)
        ';
    }
--- request
GET /test
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log
bad argument #1 to 'sleep'



=== TEST 3: sleep 0.5 in subrequest - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.location.capture("/sleep")
            local now = ngx.now()
            local delay = now - before
            ngx.say(delay)
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep(0.5)';
    }
--- request
GET /test
--- response_body_like chop
^0\.(?:4[5-9]\d*|5[0-9]\d*|5)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/sleep?"
--- no_error_log
[error]



=== TEST 4: sleep a in subrequest with bad argument
--- config
    location /test {
        content_by_lua '
            local res = ngx.location.capture("/sleep");
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep("a")';
    }
--- request
GET /test
--- response_body_like:
--- error_log
bad argument #1 to 'sleep'



=== TEST 5: sleep 0.33 - multi-times in content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local start = ngx.now()
            ngx.sleep(0.33)
            ngx.sleep(0.33)
            ngx.sleep(0.33)
            ngx.say(ngx.now() - start)
        ';
    }
--- request
GET /test
--- response_body_like chop
^(?:0\.9\d*|1\.[0-2]\d*|1)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 6: sleep 0.5 - interleaved by ngx.say() - ended by ngx.sleep
--- config
    location /test {
        content_by_lua '
            ngx.send_headers()
            -- ngx.location.capture("/sleep")
            ngx.sleep(1)
            ngx.say("blah")
            ngx.sleep(1)
            -- ngx.location.capture("/sleep")
        ';
    }
    location = /sleep {
        echo_sleep 0.1;
    }
--- request
GET /test
--- response_body
blah
--- error_log
lua ready to sleep
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 7: sleep 0.5 - interleaved by ngx.say() - not ended by ngx.sleep
--- config
    location /test {
        content_by_lua '
            ngx.send_headers()
            -- ngx.location.capture("/sleep")
            ngx.sleep(0.3)
            ngx.say("blah")
            ngx.sleep(0.5)
            -- ngx.location.capture("/sleep")
            ngx.say("hiya")
        ';
    }
    location = /sleep {
        echo_sleep 0.1;
    }
--- request
GET /test
--- response_body
blah
hiya
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 8: ngx.location.capture before and after ngx.sleep
--- config
    location /test {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)

            ngx.sleep(0.1)

            res = ngx.location.capture("/sub")
            ngx.print(res.body)
        ';
    }
    location = /hello {
        echo hello world;
    }
    location = /sub {
        proxy_pass http://127.0.0.1:$server_port/hello;
    }
--- request
GET /test
--- response_body
hello world
hello world
--- no_error_log
[error]



=== TEST 9: sleep 0
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.sleep(0)
            local now = ngx.now()
            ngx.say("elapsed: ", now - before)
        ';
    }
--- request
GET /test
--- response_body_like chop
elapsed: 0
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 10: ngx.sleep unavailable in log_by_lua
--- config
    location /t {
        echo hello;
        log_by_lua '
            ngx.sleep(0.1)
        ';
    }
--- request
GET /t
--- response_body
hello
--- wait: 0.1
--- error_log
API disabled in the context of log_by_lua*



=== TEST 11: ngx.sleep() fails to yield (xpcall err handler)
--- config
    location = /t {
        content_by_lua '
            local function f()
                return error(1)
            end
            local function err()
                ngx.sleep(0.001)
            end
            xpcall(f, err)
            ngx.say("ok")
        ';
    }
--- request
    GET /t
--- response_body
ok
--- error_log
lua clean up the timer for pending ngx.sleep
--- no_error_log
[error]



=== TEST 12: ngx.sleep() fails to yield (require)
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location = /t {
        content_by_lua '
            package.loaded["foosleep"] = nil
            require "foosleep";
        ';
    }
--- request
    GET /t
--- user_files
>>> foosleep.lua
ngx.sleep(0.001)

--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- wait: 0.2
--- error_log eval
[
"lua clean up the timer for pending ngx.sleep",
qr{runtime error: attempt to yield across (?:metamethod/)?C-call boundary},
]



=== TEST 13: sleep coctx handler did not get called in ngx.exit().
--- config
    location /t {
         content_by_lua "
            local function sleep(t)
                --- nginx return reply to client without waiting
                ngx.sleep(t)
            end

            local function wait()
                 --- worker would crash afterwards
                 xpcall(function () error(1) end, function() return sleep(0.001) end)
                 --- ngx.exit was required to crash worker
                 ngx.exit(200)
            end

            wait()
         ";
    }
--- request
    GET /t

--- wait: 0.1
--- response_body
--- no_error_log
[error]
[alert]



=== TEST 14: sleep coctx handler did not get called in ngx.exec().
--- config
    location /t {
         content_by_lua '
            local function sleep(t)
                --- nginx return reply to client without waiting
                ngx.sleep(t)
            end

            local function wait()
                 --- worker would crash afterwards
                 xpcall(function () error(1) end, function() return sleep(0.001) end)
                 --- ngx.exit was required to crash worker
                 ngx.exec("/dummy")
            end

            wait()
         ';
    }

    location /dummy {
        echo ok;
    }
--- request
    GET /t

--- wait: 0.1
--- response_body
ok
--- no_error_log
[error]
[alert]



=== TEST 15: sleep coctx handler did not get called in ngx.req.set_uri(uri, true).
--- config
    location /t {
         rewrite_by_lua '
            local function sleep(t)
                --- nginx return reply to client without waiting
                ngx.sleep(t)
            end

            local function wait()
                 --- worker would crash afterwards
                 xpcall(function () error(1) end, function() return sleep(0.001) end)
                 --- ngx.exit was required to crash worker
                 ngx.req.set_uri("/dummy", true)
            end

            wait()
         ';
    }

    location /dummy {
        echo ok;
    }
--- request
    GET /t

--- wait: 0.1
--- response_body
ok
--- no_error_log
[error]
[alert]



=== TEST 16: sleep 0
--- config
    location /t {
        content_by_lua_block {
            local function f (n)
                print("f begin ", n)
                ngx.sleep(0)
                print("f middle ", n)
                ngx.sleep(0)
                print("f end ", n)
                ngx.sleep(0)
            end

            for i = 1, 3 do
                assert(ngx.thread.spawn(f, i))
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/\bf (?:begin|middle|end)\b|\bworker cycle$|\be?poll timer: \d+$/
--- grep_error_log_out eval
qr/f begin
f begin
f begin
worker cycle
e?poll timer: 0
f middle
f middle
f middle
worker cycle
e?poll timer: 0
f end
f end
f end
worker cycle
e?poll timer: 0
/



=== TEST 17: sleep short times less than 1ms
--- config
    location /t {
        content_by_lua_block {
            local delay = 0.0005

            local function f (n)
                print("f begin ", n)
                ngx.sleep(delay)
                print("f middle ", n)
                ngx.sleep(delay)
                print("f end ", n)
                ngx.sleep(delay)
            end

            for i = 1, 3 do
                assert(ngx.thread.spawn(f, i))
            end

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/\bf (?:begin|middle|end)\b|\bworker cycle$|\be?poll timer: \d+$/
--- grep_error_log_out eval
qr/f begin
f begin
f begin
worker cycle
e?poll timer: 0
f middle
f middle
f middle
worker cycle
e?poll timer: 0
f end
f end
f end
worker cycle
e?poll timer: 0
/
