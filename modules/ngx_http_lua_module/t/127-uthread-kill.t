# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 5 + 1);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: kill pending sleep
--- config
    location /lua {
        content_by_lua '
            local function f()
                ngx.say("hello from f()")
                ngx.sleep(1)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
hello from f()
thread created: running
killed
failed to kill thread: already waited or killed

--- no_error_log
[error]
--- error_log
lua clean up the timer for pending ngx.sleep



=== TEST 2: already waited
--- config
    location /lua {
        content_by_lua '
            local function f()
                ngx.say("hello from f()")
                ngx.sleep(0.001)
                return 32
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, res = ngx.thread.wait(t)
            if not ok then
                ngx.say("failed to kill thread: ", res)
                return
            end

            ngx.say("waited: ", res)

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
hello from f()
thread created: running
waited: 32
failed to kill thread: already waited or killed

--- no_error_log
[error]
lua clean up the timer for pending ngx.sleep



=== TEST 3: kill pending resolver
--- config
    resolver 127.0.0.2:12345;
    resolver_timeout 5ms;
    location /lua {
        content_by_lua '
            local function f()
                local sock = ngx.socket.tcp()
                sock:connect("some.127.0.0.2", 12345)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
thread created: running
killed

--- no_error_log
[error]
--- error_log
lua tcp socket abort resolver



=== TEST 4: kill pending connect
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /lua {
        content_by_lua '
            local ready = false
            local function f()
                local sock = ngx.socket.tcp()
                sock:connect("agentzh.org", 80)
                sock:close()
                ready = true
                sock:settimeout(10000)
                sock:connect("127.0.0.2", 12345)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            while not ready do
                ngx.sleep(0.001)
            end

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
delete thread 2
terminate 1: ok
delete thread 1

--- response_body
thread created: running
killed

--- no_error_log
[error]
lua tcp socket abort resolver
--- grep_error_log: lua finalize socket
--- grep_error_log_out
lua finalize socket
lua finalize socket

--- error_log



=== TEST 5: cannot kill a pending subrequest
--- config
    location = /sub {
        echo_sleep 0.3;
        echo ok;
    }

    location = /t {
        content_by_lua '
            local function f()
                ngx.location.capture("/sub")
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
thread created: running
failed to kill thread: pending subrequests

--- no_error_log
[error]
[alert]
lua tcp socket abort resolver
--- error_log



=== TEST 6: cannot kill a pending subrequest not in the thread being killed
--- config
    location = /sub {
        echo_sleep 0.3;
        echo ok;
    }

    location = /t {
        content_by_lua '
            local function f()
                ngx.location.capture("/sub")
            end

            local function g()
                ngx.sleep(0.3)
            end

            local tf, err = ngx.thread.spawn(f)
            if not tf then
                ngx.say("failed to spawn thread 1: ", err)
                return
            end

            ngx.say("thread f created: ", coroutine.status(tf))

            local tg, err = ngx.thread.spawn(g)
            if not tg then
                ngx.say("failed to spawn thread g: ", err)
                return
            end

            ngx.say("thread g created: ", coroutine.status(tg))

            collectgarbage()

            local ok, err = ngx.thread.kill(tf)
            if not ok then
                ngx.say("failed to kill thread f: ", err)
            else
                ngx.say("killed f")
            end

            local ok, err = ngx.thread.kill(tg)
            if not ok then
                ngx.say("failed to kill thread g: ", err)
            else
                ngx.say("killed g")
            end
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
thread f created: running
thread g created: running
failed to kill thread f: pending subrequests
killed g

--- no_error_log
[error]
[alert]
lua tcp socket abort resolver
--- error_log



=== TEST 7: kill a thread that has done a subrequest but no pending ones
--- config
    location = /sub {
        echo ok;
    }

    location = /t {
        content_by_lua '
            local ready = false
            local function f()
                ngx.location.capture("/sub")
                ready = true
                ngx.sleep(0.5)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            while not ready do
                ngx.sleep(0.001)
            end

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
thread created: running
killed

--- no_error_log
[error]
[alert]
lua tcp socket abort resolver
--- error_log



=== TEST 8: kill a thread already terminated
--- config
    location = /t {
        content_by_lua '
            local function f()
                return
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))

            collectgarbage()

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.say("failed to kill thread: ", err)
                return
            end

            ngx.say("killed")
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
thread created: zombie
failed to kill thread: already terminated

--- no_error_log
[error]
[alert]
lua tcp socket abort resolver
--- error_log



=== TEST 9: kill self
--- config
    location = /t {
        content_by_lua '
            local ok, err = ngx.thread.kill(coroutine.running())
            if not ok then
                ngx.say("failed to kill main thread: ", err)
            else
                ngx.say("killed main thread.")
            end

            local function f()
                local ok, err = ngx.thread.kill(coroutine.running())
                if not ok then
                    ngx.say("failed to kill user thread: ", err)
                else
                    ngx.say("user thread thread.")
                end

            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.say("failed to spawn thread: ", err)
                return
            end

            ngx.say("thread created: ", coroutine.status(t))
        ';
    }
--- request
GET /t
--- stap2 eval: $::StapScript
--- response_body
failed to kill main thread: not user thread
failed to kill user thread: killer not parent
thread created: zombie

--- no_error_log
[error]
[alert]
lua tcp socket abort resolver
--- error_log
