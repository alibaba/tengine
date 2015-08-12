# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: log socket errors off (tcp)
--- config
    location /t {
        lua_socket_connect_timeout 1ms;
        lua_socket_log_errors off;
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("8.8.8.8", 80)
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- no_error_log
[error]



=== TEST 2: log socket errors on (tcp)
--- config
    location /t {
        lua_socket_connect_timeout 1ms;
        lua_socket_log_errors on;
        content_by_lua '
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect("8.8.8.8", 80)
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- error_log
lua tcp socket connect timed out



=== TEST 3: log socket errors on (udp)
--- config
    location /t {
        lua_socket_log_errors on;
        lua_socket_read_timeout 1ms;
        content_by_lua '
            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername("8.8.8.8", 80)
            ok, err = sock:receive()
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- error_log
lua udp socket read timed out



=== TEST 4: log socket errors off (udp)
--- config
    location /t {
        lua_socket_log_errors off;
        lua_socket_read_timeout 1ms;
        content_by_lua '
            local sock = ngx.socket.udp()
            local ok, err = sock:setpeername("8.8.8.8", 80)
            ok, err = sock:receive()
            ngx.say(err)
        ';
    }
--- request
GET /t
--- response_body
timeout
--- no_error_log
[error]

