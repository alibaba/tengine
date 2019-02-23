# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: exec in user thread (entry still pending)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.exec("/foo")
            end

            ngx.thread.spawn(f)
            ngx.sleep(1)
            ngx.say("hello")
        ';
        content_by_lua return;
    }

    location /foo {
        echo i am foo;
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
delete thread 1

--- response_body
i am foo
--- no_error_log
[error]



=== TEST 2: exec in user thread (entry already quits)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exec("/foo")
            end

            ngx.thread.spawn(f)
        ';
        content_by_lua return;
    }

    location /foo {
        echo i am foo;
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
i am foo
--- no_error_log
[error]



=== TEST 3: exec in user thread (entry thread is still pending on ngx.sleep)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exec("/foo")
            end

            ngx.thread.spawn(f)
            ngx.sleep(1)
        ';
        content_by_lua return;
    }

    location = /foo {
        echo hello foo;
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

--- wait: 0.1
--- response_body
hello foo
--- no_error_log
[error]



=== TEST 4: exec in a user thread (another user thread is still pending on ngx.sleep)
--- config
    location /lua {
        access_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exec("/foo")
            end

            local function g()
                ngx.sleep(1)
            end

            ngx.thread.spawn(f)
            ngx.thread.spawn(g)
        ';
        content_by_lua return;
    }

    location = /foo {
        echo hello foo;
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
hello foo
--- no_error_log
[error]



=== TEST 5: exec in user thread (entry thread is still pending on ngx.location.capture), without pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        access_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.exec("/foo")
            end

            ngx.thread.spawn(f)

            ngx.location.capture("/sleep")
            ngx.say("end")
        ';
    }

    location = /sleep {
        echo_sleep 0.2;
    }

    location = /foo {
        echo hello world;
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
end
--- error_log
attempt to abort with pending subrequests
