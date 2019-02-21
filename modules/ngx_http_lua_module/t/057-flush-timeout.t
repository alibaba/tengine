# vim:set ft= ts=4 sw=4 et fdm=marker:

BEGIN {
    if (!defined $ENV{LD_PRELOAD}) {
        $ENV{LD_PRELOAD} = '';
    }

    if ($ENV{LD_PRELOAD} !~ /\bmockeagain\.so\b/) {
        $ENV{LD_PRELOAD} = "mockeagain.so $ENV{LD_PRELOAD}";
    }

    if ($ENV{MOCKEAGAIN} eq 'r') {
        $ENV{MOCKEAGAIN} = 'rw';

    } else {
        $ENV{MOCKEAGAIN} = 'w';
    }

    $ENV{TEST_NGINX_EVENT_TYPE} = 'poll';
    $ENV{MOCKEAGAIN_WRITE_TIMEOUT_PATTERN} = 'hello, world';
    $ENV{TEST_NGINX_POSTPONE_OUTPUT} = 1;
}

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * 17;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: flush wait - timeout
--- config
    send_timeout 100ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            ngx.flush(true)
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- ignore_response
--- error_log eval
qr/client timed out \(\d+: .*?timed out\)/
--- no_error_log
[error]



=== TEST 2: send timeout timer got removed in time
--- config
    send_timeout 1234ms;
    location /test {
        content_by_lua '
            ngx.say(string.rep("blah blah blah", 10))
            -- ngx.flush(true)
            ngx.eof()
            for i = 1, 20 do
                ngx.sleep(0.1)
            end
        ';
    }
--- request
GET /test
--- stap
global evtime

F(ngx_http_handler) {
    delete evtime
}

M(timer-add) {
    if ($arg2 == 1234) {
        printf("add timer %d\n", $arg2)
        evtime[$arg1] = $arg2
    }
}

M(timer-del) {
    time = evtime[$arg1]
    if (time == 1234) {
        printf("del timer %d\n", time)
    }
}

M(timer-expire) {
    time = evtime[$arg1]
    if (time == 1234) {
        printf("expire timer %d\n", time)
        #print_ubacktrace()
    }
}
/*
probe syscall.writev.return {
    if (pid() == target()) {
        printf("writev: %s\n", retstr)
    }
}
*/
--- stap_out
add timer 1234
del timer 1234
--- ignore_response
--- no_error_log
[error]
--- timeout: 3



=== TEST 3: exit in user thread (entry thread is still pending on ngx.flush)
--- config
    send_timeout 200ms;
    location /lua {
        content_by_lua '
            local function f()
                ngx.say("hello in thread")
                ngx.sleep(0.1)
                ngx.exit(0)
            end

            ngx.say("before")
            ngx.thread.spawn(f)
            ngx.say("after")

            ngx.say("hello, world!")
            ngx.flush(true)

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

F(ngx_http_lua_coctx_cleanup) {
    println("lua tcp socket cleanup")
}

/*
F(ngx_http_finalize_request) {
    printf("finalize request: c:%d, a:%d, cb:%d, rb:%d\n", $r->main->count,
        $r == $r->connection->data, $r->connection->buffered, $r->buffered)
}

F(ngx_http_set_write_handler) {
    println("set write handler")
}
*/

F(ngx_http_lua_flush_cleanup) {
    println("lua flush cleanup")
}
_EOC_

--- stap_out
create 2 in 1
spawn user thread 2 in 1
add timer 100
add timer 200
expire timer 100
terminate 2: ok
delete thread 2
lua flush cleanup
delete timer 200
delete thread 1
add timer 200
expire timer 200
free request

--- ignore_response
--- no_error_log
[error]



=== TEST 4: flush wait - return "timeout" error
--- config
    send_timeout 100ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "failed to flush: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- ignore_response
--- error_log eval
[
qr/client timed out \(\d+: .*?timed out\)/,
'failed to flush: timeout',
]
--- no_error_log
[alert]



=== TEST 5: flush wait in multiple user threads - return "timeout" error
--- config
    send_timeout 100ms;
    location /test {
        content_by_lua '
            ngx.say("hello, world")

            local function run(tag)
                local ok, err = ngx.flush(true)
                if not ok then
                    ngx.log(ngx.ERR, "thread ", tag, ": failed to flush: ", err)
                    return
                end
                ngx.say("hiya")
            end

            local function new_thread(tag)
                local ok, err = ngx.thread.spawn(run, tag)
                if not ok then
                    return error("failed to spawn thread: ", err)
                end
            end

            new_thread("A")
            new_thread("B")
            run("main")
        ';
    }
--- request
GET /test
--- ignore_response
--- error_log eval
[
qr/client timed out \(\d+: .*?timed out\)/,
'thread main: failed to flush: timeout',
'thread A: failed to flush: timeout',
'thread B: failed to flush: timeout',
]
--- no_error_log
[alert]



=== TEST 6: flush wait - client abort connection prematurely
--- config
    #send_timeout 100ms;
    location /test {
        limit_rate 2;
        content_by_lua '
            ngx.say("hello, lua")
            local ok, err = ngx.flush(true)
            if not ok then
                ngx.log(ngx.ERR, "failed to flush: ", err)
                return
            end
            ngx.say("hiya")
        ';
    }
--- request
GET /test
--- ignore_response
--- error_log eval
[
qr/writev\(\) failed .*? Broken pipe/i,
qr/failed to flush: client aborted/,
]
--- no_error_log
[alert]

--- timeout: 0.2
--- abort
--- wait: 1
