# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 1);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';
$ENV{TEST_NGINX_REDIS_PORT} ||= '6379';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: exit in user thread (entry thread is still pending to run)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            ngx.sleep(1)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

M(timer-add) {
    if ($arg2 == 1000) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
terminate 2: ok
delete thread 2
delete thread 1

--- response_body
before
hello in thread
--- no_error_log
[error]



=== TEST 2: exit in user thread (entry thread is still pending on ngx.sleep)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            ngx.sleep(1)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 1000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 1000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_sleep_cleanup) {
    println("lua sleep cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 1000
expire timer 100
terminate 2: ok
delete thread 2
lua sleep cleanup
delete timer 1000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]
[alert]



=== TEST 3: exit in a user thread (another user thread is still pending on ngx.sleep)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.say("f")
                ngx.exit(0)
            end

            local function g()
                ngx.sleep(1)
                ngx.say("g")
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(g)
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 1000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 1000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 1000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_sleep_cleanup) {
    println("lua sleep cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
create 3 in 1
spawn user thread 3 in 1
add timer 1000
terminate 1: ok
delete thread 1
expire timer 100
terminate 2: ok
delete thread 2
lua sleep cleanup
delete timer 1000
delete thread 3
free request

--- response_body
end
f
--- no_error_log
[error]



=== TEST 4: exit in user thread (entry already quits)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.say("exiting the user thread")
                ngx.exit(0)
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

--- wait: 0.1
--- response_body
before
after
exiting the user thread
--- no_error_log
[error]



=== TEST 5: exit in user thread (entry thread is still pending on the DNS resolver for ngx.socket.tcp)
--- config
    location /lua {
        resolver 127.0.0.2:12345;
        resolver_timeout 12s;
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.001)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_resolve_start) {
    println("resolver started")
}

F(ngx_http_lua_socket_resolve_handler) {
    println("resolver done")
}

F(ngx_http_free_request) {
    println("free request")
}

F(ngx_resolve_name) {
    printf("resolving %s\n", user_string_n($ctx->name->data, $ctx->name->len))
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 1) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 1) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 12000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 1) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_tcp_resolve_cleanup) {
    println("lua tcp resolve cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 1
resolver started
resolving agentzh.org
add timer 12000
expire timer 1
terminate 2: ok
delete thread 2
lua tcp resolve cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 6: exit in user thread (entry thread is still pending on the DNS resolver for ngx.socket.udp)
--- config
    location /lua {
        resolver 127.0.0.2:12345;
        #resolver 127.0.0.1;
        resolver_timeout 12s;
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.001)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername("agentzh.org", 80)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_resolve_start) {
    println("resolver started")
}

F(ngx_http_lua_socket_resolve_handler) {
    println("resolver done")
}

F(ngx_http_free_request) {
    println("free request")
}

F(ngx_resolve_name) {
    printf("resolving %s\n", user_string_n($ctx->name->data, $ctx->name->len))
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 1) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 1) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 12000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 1) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_udp_resolve_cleanup) {
    println("lua udp resolve cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 1
resolver started
resolving agentzh.org
add timer 12000
expire timer 1
terminate 2: ok
delete thread 2
lua udp resolve cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 7: exit in user thread (entry thread is still pending on tcpsock:connect)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.tcp()
            sock:settimeout(12000)
            local ok, err = sock:connect("127.0.0.2", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end
            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
    /*
    if (tm == 12000) {
        print_ubacktrace()
    }
    */
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua tcp socket cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 8: exit in user thread (entry thread is still pending on tcpsock:receive)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, ok = sock:send("blpop not_exists 2\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            sock:settimeout(12000)

            local data, err = sock:receive()
            if not data then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua tcp socket cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 9: exit in user thread (entry thread is still pending on tcpsock:receiveuntil's iterator)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.tcp()

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, ok = sock:send("blpop not_exists 2\\r\\n")
            if not bytes then
                ngx.say("failed to send: ", err)
                return
            end

            local it, err = sock:receiveuntil("\\r\\n")
            if not it then
                ngx.say("failed to receive until: ", err)
                return
            end

            sock:settimeout(12000)

            local data, err = it()
            if not data then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua tcp socket cleanup
delete timer 12000
delete thread 1
free request

--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 10: exit in user thread (entry thread is still pending on udpsock:receive)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.socket.udp()

            local ok, err = sock:setpeername("8.8.8.8", 12345)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            sock:settimeout(12000)

            local data, err = sock:receive()
            if not data then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("end")
        ';
    }
--- request
GET /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_udp_socket_cleanup) {
    println("lua udp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua udp socket cleanup
delete timer 12000
delete thread 1
free request

--- wait: 0.1
--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 11: exit in user thread (entry thread is still pending on reqsock:receive)
--- config
    location /lua {
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")
            local sock = ngx.req.socket()

            sock:settimeout(12000)

            local data, err = sock:receive(1024)
            if not data then
                ngx.say("failed to receive: ", err)
                return
            end

            ngx.say("end")
        ';
    }
--- request
POST /lua

--- more_headers
Content-Length: 1024

--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua tcp socket cleanup
delete timer 12000
delete thread 1
free request

--- wait: 0.1
--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 12: exit in user thread (entry thread is still pending on ngx.req.read_body)
--- config
    location /lua {
        client_body_timeout 12000ms;
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")

            ngx.req.read_body()

            ngx.say("end")
        ';
    }
--- request
POST /lua
--- more_headers
Content-Length: 1024
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 12000 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 12000 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_req_body_cleanup) {
    println("lua req body cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 12000
expire timer 100
terminate 2: ok
delete thread 2
lua req body cleanup
delete timer 12000
delete thread 1
free request

--- wait: 0.1
--- response_body
before
hello in thread
after
--- no_error_log
[error]



=== TEST 13: exit in user thread (entry thread is still pending on ngx.location.capture), with pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        rewrite_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")

            ngx.location.capture("/sleep")

            ngx.say("end")
        ';
    }

    location = /sleep {
        echo_sleep 0.2;
    }
--- request
POST /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 200 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 200
expire timer 100
terminate 2: fail
expire timer 200
terminate 1: ok
delete thread 2
delete thread 1
free request

--- wait: 0.1
--- response_body
before
hello in thread
after
end
--- error_log
attempt to abort with pending subrequests



=== TEST 14: exit in user thread (entry thread is still pending on ngx.location.capture), without pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        rewrite_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.thread.spawn(f)

            ngx.location.capture("/sleep")
            ngx.say("end")
        ';
    }

    location = /sleep {
        echo_sleep 0.2;
    }
--- request
POST /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 200 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_post_subrequest) {
    printf("post subreq %s\n", ngx_http_req_uri($r))
}

_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 200
expire timer 100
terminate 2: fail
expire timer 200
post subreq /sleep
terminate 1: ok
delete thread 2
delete thread 1
free request

--- wait: 0.1
--- response_body
end
--- error_log
attempt to abort with pending subrequests



=== TEST 15: exit in user thread (entry thread is still pending on ngx.location.capture_multi), without pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        rewrite_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.thread.spawn(f)

            ngx.location.capture_multi{
                {"/echo"},
                {"/sleep"}
            }
            ngx.say("end")
        ';
    }

    location = /echo {
        echo hello;
    }

    location = /sleep {
        echo_sleep 0.2;
    }
--- request
POST /lua
--- stap2 eval: $::StapScript
--- stap eval
<<'_EOC_' . $::GCScript;

global timers

F(ngx_http_free_request) {
    println("free request")
}

M(timer-add) {
    if ($arg2 == 200 || $arg2 == 100) {
        timers[$arg1] = $arg2
        printf("add timer %d\n", $arg2)
    }
}

M(timer-del) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("delete timer %d\n", tm)
        delete timers[$arg1]
    }
}

M(timer-expire) {
    tm = timers[$arg1]
    if (tm == 200 || tm == 100) {
        printf("expire timer %d\n", timers[$arg1])
        delete timers[$arg1]
    }
}

F(ngx_http_lua_post_subrequest) {
    printf("post subreq %s\n", ngx_http_req_uri($r))
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
post subreq /echo
add timer 200
expire timer 100
terminate 2: fail
expire timer 200
post subreq /sleep
terminate 1: ok
delete thread 2
delete thread 1
free request

--- wait: 0.1
--- response_body
end
--- error_log
attempt to abort with pending subrequests
