# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

our $HtmlDir = html_dir;

#$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

no_long_string();
#no_diff();
#log_level 'warn';

run_tests();

__DATA__

=== TEST 1: receive
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.req.socket()
            sock.receive("l")
        ';
    }
--- request
    POST /t
--- more_headers: Content-Length: 1024
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'receive' (table expected, got string)



=== TEST 2: receiveuntil
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.req.socket()
            sock.receiveuntil(32, "ab")
        ';
    }
--- request
    POST /t
--- more_headers: Content-Length: 1024
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'receiveuntil' (table expected, got number)



=== TEST 3: send (bad arg number)
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.socket.tcp()
            sock.send("hello")
        ';
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
expecting 2 arguments (including the object), but got 1



=== TEST 4: send (bad self)
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.socket.tcp()
            sock.send("hello", 32)
        ';
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'send' (table expected, got string)



=== TEST 5: getreusedtimes (bad self)
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.socket.tcp()
            sock.getreusedtimes(2)
        ';
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'getreusedtimes' (table expected, got number)



=== TEST 6: close (bad self)
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.socket.tcp()
            sock.close(2)
        ';
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'close' (table expected, got number)



=== TEST 7: setkeepalive (bad self)
--- config
    location /t {
        content_by_lua '
            local sock, err = ngx.socket.tcp()
            sock.setkeepalive(2)
        ';
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #1 to 'setkeepalive' (table expected, got number)
