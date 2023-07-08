# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use t::StapThread;

our $GCScript = <<_EOC_;
$t::StapThread::GCScript

F(ngx_http_lua_check_broken_connection) {
    println("lua check broken conn")
}

F(ngx_http_lua_request_cleanup) {
    println("lua req cleanup")
}
_EOC_

our $StapScript = $t::StapThread::StapScript;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 15);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';
$ENV{TEST_NGINX_REDIS_PORT} ||= '6379';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: ignore the client abort event in the user callback
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.sleep(0.7)
            ngx.log(ngx.NOTICE, "main handler done")
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: ok
terminate 1: ok
delete thread 2
delete thread 1
terminate 3: ok
delete thread 3
lua req cleanup

--- timeout: 0.2
--- abort
--- wait: 0.7
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
on abort called
main handler done



=== TEST 2: abort in the user callback
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(444)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.sleep(0.7)
            ngx.log(ngx.NOTICE, "main handler done")
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: ok
lua req cleanup
delete thread 2
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
main handler done
--- error_log
client prematurely closed connection
on abort called



=== TEST 3: ngx.exit(499) with pending subrequest
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(499)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.location.capture("/sleep")
        ';
        content_by_lua return;
    }

    location = /sleep {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: ok
lua req cleanup
delete thread 2
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
on abort called



=== TEST 4: ngx.exit(408) with pending subrequest
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(408)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.location.capture("/sleep")
        ';
        content_by_lua return;
    }

    location = /sleep {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: ok
lua req cleanup
delete thread 2
delete thread 1

--- timeout: 0.2
--- abort
--- wait: 0.1
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
on abort called



=== TEST 5: ngx.exit(-1) with pending subrequest
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(-1)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.location.capture("/sleep")
        ';
    }

    location = /sleep {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: ok
lua req cleanup
delete thread 2
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
on abort called



=== TEST 6: ngx.exit(0) with pending subrequest
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(0)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.location.capture("/sleep")
            ngx.log(ngx.ERR, "main handler done")
        ';
        content_by_lua return;
    }

    location = /sleep {
        echo_sleep 0.7;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
lua check broken conn
terminate 2: fail
terminate 1: ok
delete thread 2
delete thread 1
terminate 3: ok
delete thread 3
lua req cleanup

--- timeout: 0.2
--- abort
--- wait: 0.6
--- ignore_response
--- error_log eval
[
'client prematurely closed connection',
'on abort called',
qr/lua user thread aborted: runtime error: access_by_lua\(nginx\.conf:\d+\):4: attempt to abort with pending subrequests/,
'main handler done',
]



=== TEST 7: accessing cosocket in callback
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
                if not ok then
                    ngx.log(ngx.ERR, "failed to connect to redis: ", err)
                    ngx.exit(499)
                end
                local bytes, err = sock:send("flushall\\r\\n")
                if not bytes then
                    ngx.log(ngx.ERR, "failed to send query: ", err)
                    ngx.exit(499)
                end

                local res, err = sock:receive()
                if not res then
                    ngx.log(ngx.ERR, "failed to receive: ", err)
                    ngx.exit(499)
                end
                ngx.log(ngx.NOTICE, "callback done: ", res)
                ngx.exit(499)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.sleep(0.7)
            ngx.log(ngx.NOTICE, "main handler done")
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like chop
^create 2 in 1
lua check broken conn
(?:lua check broken conn
)?terminate 2: ok
lua req cleanup
delete thread 2
delete thread 1
$
--- timeout: 0.2
--- abort
--- wait: 0.2
--- ignore_response
--- no_error_log
[error]
main handler done
--- error_log
client prematurely closed connection
on abort called
callback done: +OK



=== TEST 8: ignore the client abort event in the user callback (no check)
--- config
    location /t {
        lua_check_client_abort off;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                ngx.say("cannot set on_abort: ", err)
                return
            end

            ngx.sleep(0.7)
            ngx.log(ngx.NOTICE, "main handler done")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1
lua req cleanup

--- timeout: 0.2
--- abort
--- response_body
cannot set on_abort: lua_check_client_abort is off
--- no_error_log
client prematurely closed connection
on abort called
main handler done



=== TEST 9: register on_abort callback but no client abortion
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.say("done")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
lua req cleanup
delete thread 2

--- response_body
done
--- no_error_log
[error]
client prematurely closed connection
on abort called
main handler done



=== TEST 10: ignore the client abort event in the user callback (uthread)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.thread.spawn(function ()
                ngx.sleep(0.7)
                ngx.log(ngx.NOTICE, "main handler done")
            end)
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
lua check broken conn
terminate 2: ok
delete thread 2
terminate 3: ok
delete thread 3
terminate 4: ok
delete thread 4
lua req cleanup

--- timeout: 0.2
--- abort
--- wait: 0.7
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
on abort called
main handler done



=== TEST 11: abort in the user callback (uthread)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
                ngx.exit(444)
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.thread.spawn(function ()
                ngx.sleep(0.7)
                ngx.log(ngx.NOTICE, "main handler done")
            end)
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
lua check broken conn
terminate 2: ok
lua req cleanup
delete thread 2
delete thread 3

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
main handler done
--- error_log
client prematurely closed connection
on abort called



=== TEST 12: register on_abort callback but no client abortion (uthread)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                error("cannot set on_abort: " .. err)
            end

            ngx.thread.spawn(function ()
                ngx.sleep(0.1)
                ngx.say("done")
            end)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
create 3 in 1
spawn user thread 3 in 1
terminate 1: ok
delete thread 1
terminate 3: ok
delete thread 3
lua req cleanup
delete thread 2

--- response_body
done
--- no_error_log
[error]
client prematurely closed connection
on abort called
main handler done



=== TEST 13: register on_abort callback multiple times
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                ngx.say("1: cannot set on_abort: " .. err)
                return
            end

            local ok, err = ngx.on_abort(function ()
                ngx.log(ngx.NOTICE, "on abort called")
            end)

            if not ok then
                ngx.say("2: cannot set on_abort: " .. err)
                return
            end

            ngx.thread.spawn(function ()
                ngx.sleep(0.1)
                ngx.say("done")
            end)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
create 2 in 1
terminate 1: ok
delete thread 1
lua req cleanup
delete thread 2

--- response_body
2: cannot set on_abort: duplicate call

--- no_error_log
[error]
