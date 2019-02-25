# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 1);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: simple user thread without I/O
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("hello in thread")
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
GET /lua
--- stap2 eval
<<'_EOC_' . $::StapScript;

F(ngx_http_lua_send_chain_link) {
    printf("send link %p\n", $in)
}

F(ngx_http_core_content_phase) {
    println("core content phase")
}

_EOC_
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 2: two simple user threads without I/O
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("in thread 1")
            end

            local function g()
                ngx.say("in thread 2")
            end

            ngx.say("before 1")
            ngx.thread.spawn(f)
            ngx.say("after 1")

            ngx.say("before 2")
            ngx.thread.spawn(g)
            ngx.say("after 2")
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
create 3 in 1
spawn user thread 3 in 1
terminate 3: ok
terminate 1: ok
delete thread 2
delete thread 3
delete thread 1

--- response_body
before 1
in thread 1
after 1
before 2
in thread 2
after 2
--- no_error_log
[error]



=== TEST 3: simple user thread with sleep
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("before sleep")
                ngx.sleep(0.1)
                ngx.say("after sleep")
            end

            ngx.say("before thread create")
            ngx.thread.spawn(f)
            ngx.say("after thread create")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
before thread create
before sleep
after thread create
after sleep
--- no_error_log
[error]



=== TEST 4: two simple user threads with sleep
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("1: before sleep")
                ngx.sleep(0.2)
                ngx.say("1: after sleep")
            end

            local function g()
                ngx.say("2: before sleep")
                ngx.sleep(0.1)
                ngx.say("2: after sleep")
            end

            ngx.say("1: before thread create")
            ngx.thread.spawn(f)
            ngx.say("1: after thread create")

            ngx.say("2: before thread create")
            ngx.thread.spawn(g)
            ngx.say("2: after thread create")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
terminate 3: ok
delete thread 3
terminate 2: ok
delete thread 2

--- wait: 0.1
--- response_body
1: before thread create
1: before sleep
1: after thread create
2: before thread create
2: before sleep
2: after thread create
2: after sleep
1: after sleep
--- no_error_log
[error]



=== TEST 5: error in user thread
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.blah()
            end

            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: fail
terminate 1: ok
delete thread 2
delete thread 1

--- response_body
after
--- error_log eval
qr/lua user thread aborted: runtime error: access_by_lua\(nginx\.conf:\d+\):3: attempt to call field 'blah' \(a nil value\)/



=== TEST 6: simple user threads doing a single subrequest (entry quits early)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("before capture")
                local res = ngx.location.capture("/proxy")
                ngx.say("after capture: ", res.body)
            end

            ngx.say("before thread create")
            ngx.thread.spawn(f)
            ngx.say("after thread create")
        ';
    }

    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location /foo {
        echo_sleep 0.1;
        echo -n hello world;
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
before thread create
before capture
after thread create
after capture: hello world
--- no_error_log
[error]



=== TEST 7: simple user threads doing a single subrequest (entry also does a subrequest and quits early)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("before capture")
                local res = ngx.location.capture("/proxy?foo")
                ngx.say("after capture: ", res.body)
            end

            ngx.say("before thread create")
            ngx.thread.spawn(f)
            ngx.say("after thread create")
            local res = ngx.location.capture("/proxy?bar")
            ngx.say("capture: ", res.body)
        ';
    }

    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/$args;
    }

    location /foo {
        echo_sleep 0.1;
        echo -n hello foo;
    }

    location /bar {
        echo -n hello bar;
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
before thread create
before capture
after thread create
capture: hello bar
after capture: hello foo
--- no_error_log
[error]



=== TEST 8: simple user threads doing a single subrequest (entry also does a subrequest and quits late)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("before capture")
                local res = ngx.location.capture("/proxy?foo")
                ngx.say("after capture: ", res.body)
            end

            ngx.say("before thread create")
            ngx.thread.spawn(f)
            ngx.say("after thread create")
            local res = ngx.location.capture("/proxy?bar")
            ngx.say("capture: ", res.body)
        ';
        content_by_lua return;
    }

    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/$args;
    }

    location /foo {
        echo_sleep 0.1;
        echo -n hello foo;
    }

    location /bar {
        echo_sleep 0.2;
        echo -n hello bar;
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1

--- response_body
before thread create
before capture
after thread create
after capture: hello foo
capture: hello bar
--- no_error_log
[error]



=== TEST 9: two simple user threads doing single subrequests (entry also does a subrequest and quits between)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("f: before capture")
                local res = ngx.location.capture("/proxy?foo")
                ngx.say("f: after capture: ", res.body)
            end

            local function g()
                ngx.say("g: before capture")
                local res = ngx.location.capture("/proxy?bah")
                ngx.say("g: after capture: ", res.body)
            end

            ngx.say("before thread 1 create")
            ngx.thread.spawn(f)
            ngx.say("after thread 1 create")

            ngx.say("before thread 2 create")
            ngx.thread.spawn(g)
            ngx.say("after thread 2 create")

            local res = ngx.location.capture("/proxy?bar")
            ngx.say("capture: ", res.body)
        ';
    }

    location /proxy {
        proxy_pass http://127.0.0.1:$server_port/$args;
    }

    location /foo {
        echo_sleep 0.1;
        echo -n hello foo;
    }

    location /bar {
        echo_sleep 0.2;
        echo -n hello bar;
    }

    location /bah {
        echo_sleep 0.3;
        echo -n hello bah;
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1
terminate 3: ok
delete thread 3

--- response_body
before thread 1 create
f: before capture
after thread 1 create
before thread 2 create
g: before capture
after thread 2 create
f: after capture: hello foo
capture: hello bar
g: after capture: hello bah
--- no_error_log
[error]



=== TEST 10: nested user threads
--- config
    location /lua {
        access_by_lua '
            local g
            local function f()
                ngx.say("before g")
                ngx.thread.spawn(g)
                ngx.say("after g")
            end

            function g()
                ngx.say("hello in g()")
            end

            ngx.say("before f")
            ngx.thread.spawn(f)
            ngx.say("after f")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 3
delete thread 2

--- response_body
before f
before g
hello in g()
after f
after g
--- no_error_log
[error]



=== TEST 11: nested user threads (with I/O)
--- config
    location /lua {
        access_by_lua '
            local g
            local function f()
                ngx.say("before g")
                ngx.thread.spawn(g)
                ngx.say("after g")
            end

            function g()
                ngx.sleep(0.1)
                ngx.say("hello in g()")
            end

            ngx.say("before f")
            ngx.thread.spawn(f)
            ngx.say("after f")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
before f
before g
after f
after g
hello in g()
--- no_error_log
[error]



=== TEST 12: coroutine status of a running user thread
--- config
    location /lua {
        access_by_lua '
            local co
            local function f()
                co = coroutine.running()
                ngx.sleep(0.1)
            end

            ngx.thread.spawn(f)
            ngx.say("status: ", coroutine.status(co))
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
status: running
--- no_error_log
[error]



=== TEST 13: coroutine status of a dead user thread
--- config
    location /lua {
        access_by_lua '
            local co
            local function f()
                co = coroutine.running()
            end

            ngx.thread.spawn(f)
            ngx.say("status: ", coroutine.status(co))
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
terminate 1: ok
delete thread 2
delete thread 1

--- response_body
status: zombie
--- no_error_log
[error]



=== TEST 14: coroutine status of a "normal" user thread
--- config
    location /lua {
        access_by_lua '
            local co
            local g
            local function f()
                co = coroutine.running()
                local co2 = coroutine.create(g)
                coroutine.resume(co2)
            end

            function g()
                ngx.sleep(0.1)
            end

            ngx.thread.spawn(f)
            ngx.say("status: ", coroutine.status(co))
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 2
terminate 1: ok
delete thread 1
terminate 3: ok
terminate 2: ok
delete thread 2

--- response_body
status: normal
--- no_error_log
[error]



=== TEST 15: creating user threads in a user coroutine
--- config
    location /lua {
        access_by_lua '
            local g
            local function f()
                ngx.say("before g")
                ngx.thread.spawn(g)
                ngx.say("after g")
            end

            function g()
                ngx.say("hello in g()")
            end

            ngx.say("before f")
            local co = coroutine.create(f)
            coroutine.resume(co)
            ngx.say("after f")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 2
spawn user thread 3 in 2
terminate 3: ok
terminate 2: ok
delete thread 3
terminate 1: ok
delete thread 1

--- response_body
before f
before g
hello in g()
after g
after f
--- no_error_log
[error]



=== TEST 16: manual time slicing between a user thread and the entry thread
--- config
    location /lua {
        access_by_lua '
            local yield = coroutine.yield

            local function f()
                local self = coroutine.running()
                ngx.say("f 1")
                yield(self)
                ngx.say("f 2")
                yield(self)
                ngx.say("f 3")
            end

            local self = coroutine.running()
            ngx.say("0")
            yield(self)
            ngx.say("1")
            ngx.thread.spawn(f)
            ngx.say("2")
            yield(self)
            ngx.say("3")
            yield(self)
            ngx.say("4")
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
terminate 1: ok
delete thread 2
delete thread 1

--- response_body
0
1
f 1
2
f 2
3
f 3
4
--- no_error_log
[error]



=== TEST 17: manual time slicing between two user threads
--- config
    location /lua {
        access_by_lua '
            local yield = coroutine.yield

            local function f()
                local self = coroutine.running()
                ngx.say("f 1")
                yield(self)
                ngx.say("f 2")
                yield(self)
                ngx.say("f 3")
            end

            local function g()
                local self = coroutine.running()
                ngx.say("g 1")
                yield(self)
                ngx.say("g 2")
                yield(self)
                ngx.say("g 3")
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(g)
            ngx.say("done")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3

--- response_body
f 1
g 1
f 2
done
g 2
f 3
g 3
--- no_error_log
[error]



=== TEST 18: entry thread and a user thread flushing at the same time
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("hello in thread")
                coroutine.yield(coroutine.running)
                ngx.flush(true)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            ngx.flush(true)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 19: two user threads flushing at the same time
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.say("hello from f")
                ngx.flush(true)
            end

            local function g()
                ngx.say("hello from g")
                ngx.flush(true)
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(g)
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like
^(?:create 2 in 1
spawn user thread 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3|create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
create 3 in 1
spawn user thread 3 in 1
terminate 3: ok
terminate 1: ok
delete thread 2
delete thread 3
delete thread 1)$

--- response_body
hello from f
hello from g
--- no_error_log
[error]



=== TEST 20: user threads + ngx.socket.tcp
--- config
    location /lua {
        access_by_lua '
            local function f()
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end
                local bytes, err = sock:send("flush_all\\r\\n")
                if not bytes then
                    ngx.say("failed to send query: ", err)
                    return
                end

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end

                ngx.say("received: ", line)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2

--- response_body
before
after
received: OK
--- no_error_log
[error]



=== TEST 21: user threads + ngx.socket.udp
--- config
    location /lua {
        access_by_lua '
            local function f()
                local sock = ngx.socket.udp()
                local ok, err = sock:setpeername("127.0.0.1", 12345)
                local bytes, err = sock:send("blah")
                if not bytes then
                    ngx.say("failed to send query: ", err)
                    return
                end

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive: ", err)
                    return
                end

                ngx.say("received: ", line)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like chop
^(?:create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
|create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1)$

--- udp_listen: 12345
--- udp_query: blah
--- udp_reply: hello udp
--- response_body_like chop
^(?:before
after
received: hello udp
|before
received: hello udp
after)$

--- no_error_log
[error]



=== TEST 22: simple user thread with ngx.req.read_body()
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.req.read_body()
                local body = ngx.req.get_body_data()
                ngx.say("body: ", body)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
POST /lua
hello world
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like chop
^(?:create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1|create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2)$

--- response_body_like chop
^(?:before
body: hello world
after|before
after
body: hello world)$

--- no_error_log
[error]



=== TEST 23: simple user thread with ngx.req.socket()
--- config
    location /lua {
        access_by_lua '
            local function f()
                local sock = ngx.req.socket()
                local body, err = sock:receive(11)
                if not body then
                    ngx.say("failed to read body: ", err)
                    return
                end

                ngx.say("body: ", body)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
        ';
    }
--- request
POST /lua
hello world
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like chop
^(?:create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1|create 2 in 1
spawn user thread 2 in 1
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2)$

--- response_body_like chop
^(?:before
body: hello world
after|before
after
body: hello world)$

--- no_error_log
[error]
