# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = $t::StapThread::GCScript;
our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';
$ENV{TEST_NGINX_REDIS_PORT} ||= '6379';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: ngx.redirect() in user thread (entry thread is still pending on ngx.location.capture_multi), without pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        content_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.redirect(301)
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



=== TEST 2: redirect in user thread (entry thread is still pending on ngx.sleep)
--- config
    location /lua {
        content_by_lua '
            local function f()
                ngx.sleep(0.1)
                ngx.redirect(301)
            end

            ngx.thread.spawn(f)
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

--- response_body_like: 302 Found
--- error_code: 302
--- no_error_log
[error]



=== TEST 3: ngx.redirect() in entry thread (user thread is still pending on ngx.location.capture_multi), without pending output
--- config
    location /lua {
        client_body_timeout 12000ms;
        content_by_lua '
            local function f()
                ngx.location.capture_multi{
                    {"/echo"},
                    {"/sleep"}
                }
                ngx.say("end")
            end

            ngx.thread.spawn(f)

            ngx.sleep(0.1)
            ngx.redirect(301)
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
terminate 1: fail
delete thread 2
delete thread 1
delete timer 200
free request

--- ignore_response
--- error_log
attempt to abort with pending subrequests
--- no_error_log
[alert]
[warn]
