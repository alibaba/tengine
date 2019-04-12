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

plan tests => repeat_each() * (blocks() * 3 - 1);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= '11211';
$ENV{TEST_NGINX_REDIS_PORT} ||= '6379';

#no_shuffle();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.sleep(1)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- wait: 0.1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 2: sleep + stop (log handler still gets called)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.sleep(1)
        ';
        log_by_lua '
            ngx.log(ngx.NOTICE, "here in log by lua")
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- wait: 0.1
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
here in log by lua



=== TEST 3: sleep + ignore
--- config
    location /t {
        lua_check_client_abort off;
        access_by_lua '
            ngx.sleep(1)
        ';
        content_by_lua return;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]



=== TEST 4: subrequest + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.location.capture("/sub")
            error("bad things happen")
        ';
    }

    location /sub {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 5: subrequest + ignore
--- config
    location /t {
        lua_check_client_abort off;
        access_by_lua '
            ngx.location.capture("/sub")
            error("bad things happen")
        ';
    }

    location /sub {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: fail
lua req cleanup
delete thread 1

--- wait: 1.1
--- timeout: 0.2
--- abort
--- ignore_response
--- error_log
bad things happen



=== TEST 6: subrequest + stop (proxy, ignore client abort)
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.location.capture("/sub")
            error("bad things happen")
        ';
    }

    location = /sub {
        proxy_ignore_client_abort on;
        proxy_pass http://127.0.0.2:12345/;
    }

    location = /sleep {
        lua_check_client_abort on;
        access_by_lua '
            ngx.sleep(1)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 7: subrequest + stop (proxy, check client abort)
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.location.capture("/sub")
            error("bad things happen")
        ';
    }

    location = /sub {
        proxy_ignore_client_abort off;
        proxy_pass http://127.0.0.2:12345/;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 8: need body on + sleep + stop (log handler still gets called)
--- config
    location /t {
        lua_check_client_abort on;
        lua_need_request_body on;
        access_by_lua '
            ngx.sleep(1)
        ';
        log_by_lua '
            ngx.log(ngx.NOTICE, "here in log by lua")
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
here in log by lua



=== TEST 9: ngx.req.read_body + sleep + stop (log handler still gets called)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.req.read_body()
            ngx.sleep(1)
        ';
        log_by_lua '
            ngx.log(ngx.NOTICE, "here in log by lua")
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection
here in log by lua



=== TEST 10: ngx.req.socket + receive() + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            sock:receive()
            ngx.sleep(1)
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 11: ngx.req.socket + receive(N) + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            sock:receive(5)
            ngx.sleep(1)
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua check broken conn
lua req cleanup
delete thread 1

--- wait: 0.1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 12: ngx.req.socket + receive(n) + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            sock:receive(2)
            ngx.sleep(1)
        ';
        content_by_lua return;
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out_like
^(?:lua check broken conn
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup|lua check broken conn
lua req cleanup
delete thread 1)$

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]



=== TEST 13: ngx.req.socket + m * receive(n) + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            sock:receive(2)
            sock:receive(2)
            sock:receive(1)
            ngx.sleep(1)
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua check broken conn
lua req cleanup
delete thread 1

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 14: ngx.req.socket + receiveuntil + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            local it = sock:receiveuntil("\\n")
            it()
            ngx.sleep(1)
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 15: ngx.req.socket + receiveuntil + it(n) + sleep + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            local it = sock:receiveuntil("\\n")
            it(2)
            it(3)
            ngx.sleep(1)
        ';
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 16: cosocket + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.req.discard_body()

            local sock, err = ngx.socket.tcp()
            if not sock then
                ngx.log(ngx.ERR, "failed to get socket: ", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_REDIS_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return
            end

            local bytes, err = sock:send("blpop nonexist 2\\r\\n")
            if not bytes then
                ngx.log(ngx.ERR, "failed to send query: ", err)
                return
            end

            -- ngx.log(ngx.ERR, "about to receive")

            local res, err = sock:receive()
            if not res then
                ngx.log(ngx.ERR, "failed to receive query: ", err)
                return
            end

            ngx.log(ngx.ERR, "res: ", res)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua req cleanup
delete thread 1

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 17: ngx.req.socket + receive n < content-length + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            local res, err = sock:receive("*a")
            if not res then
                ngx.log(ngx.NOTICE, "failed to receive: ", err)
                return
            end
            error("bad")
        ';
        content_by_lua return;
    }
--- raw_request eval
"POST /t HTTP/1.0\r
Host: localhost\r
Connection: close\r
Content-Length: 100\r
\r
hello"
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
failed to receive: client aborted



=== TEST 18: ngx.req.socket + receive n == content-length + stop
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            local sock = ngx.req.socket()
            local res, err = sock:receive("*a")
            if not res then
                ngx.log(ngx.NOTICE, "failed to receive: ", err)
                return
            end
            ngx.sleep(1)
            error("bad")
        ';

        content_by_lua return;
    }
--- raw_request eval
"POST /t HTTP/1.0\r
Host: localhost\r
Connection: close\r
Content-Length: 5\r
\r
hello"
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
lua check broken conn
lua check broken conn
lua req cleanup
delete thread 1

--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
--- error_log
client prematurely closed connection



=== TEST 19: ngx.req.socket + receive n == content-length + ignore
--- config
    location /t {
        access_by_lua '
            local sock = ngx.req.socket()
            local res, err = sock:receive("*a")
            if not res then
                ngx.log(ngx.NOTICE, "failed to receive: ", err)
                return
            end
            ngx.say("done")
        ';
        content_by_lua return;
    }
--- raw_request eval
"POST /t HTTP/1.0\r
Host: localhost\r
Connection: close\r
Content-Length: 5\r
\r
hello"
--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup

--- shutdown: 1
--- ignore_response
--- no_error_log
[error]
[alert]



=== TEST 20: ngx.req.read_body + sleep + stop (log handler still gets called)
--- config
    location /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.req.read_body()
        ';
        content_by_lua return;
    }
--- request
POST /t
hello

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup

--- shutdown: 1
--- wait: 0.1
--- ignore_response
--- no_error_log
[error]



=== TEST 21: exec to lua + ignore
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.exec("/t2")
        ';
    }

    location = /t2 {
        lua_check_client_abort off;
        content_by_lua '
            ngx.sleep(1)
        ';
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
lua req cleanup
delete thread 1
terminate 2: ok
delete thread 2
lua req cleanup

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
[alert]



=== TEST 22: exec to proxy + ignore
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.exec("/t2")
        ';
    }

    location = /t2 {
        proxy_ignore_client_abort on;
        proxy_pass http://127.0.0.1:$server_port/sleep;
    }

    location = /sleep {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
lua req cleanup
delete thread 1

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
[alert]



=== TEST 23: exec (named location) to proxy + ignore
--- config
    location = /t {
        lua_check_client_abort on;
        access_by_lua '
            ngx.exec("@t2")
        ';
    }

    location @t2 {
        proxy_ignore_client_abort on;
        proxy_pass http://127.0.0.1:$server_port/sleep;
    }

    location = /sleep {
        echo_sleep 1;
    }
--- request
GET /t

--- stap2 eval: $::StapScript
--- stap eval: $::GCScript
--- stap_out
terminate 1: ok
lua req cleanup
delete thread 1

--- wait: 1
--- timeout: 0.2
--- abort
--- ignore_response
--- no_error_log
[error]
[alert]
