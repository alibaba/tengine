# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

# more times than usual(2) for test case 6
repeat_each(4);

plan tests => repeat_each() * (blocks() * 3 + 7);

our $HtmlDir = html_dir;

# get ip address in the dev which is default route outgoing dev
my $dev = `ip route | awk '/default/ {printf "%s", \$5}'`;
my $local_ip = `ip route | grep $dev | grep -o "src .*" | head -n 1 | awk '{print \$2}'`;
chomp $local_ip;

$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;
$ENV{TEST_NGINX_NOT_EXIST_IP} ||= '8.8.8.8';
$ENV{TEST_NGINX_INVALID_IP} ||= '127.0.0.1:8899';
$ENV{TEST_NGINX_SERVER_IP} ||= $local_ip;

no_long_string();
#no_diff();

#log_level 'warn';
log_level 'debug';

no_shuffle();

run_tests();

__DATA__

=== TEST 1: upstream sockets bind 127.0.0.1
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local ip = "127.0.0.1"
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local bytes, err = sock:send("GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent")

            local reader = sock:receiveuntil("\r\n0\r\n\r\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response")
            local remote_ip = string.match(data, "(bind: %d+%.%d+%.%d+%.%d+)")
            ngx.say(remote_ip)

            ngx.say("done")
        }
    }

    location /foo {
        echo bind: $remote_addr;
    }
--- request
GET /t
--- response_body
connected: 1
request sent
received response
bind: 127.0.0.1
done
--- no_error_log
["[error]",
"bind(127.0.0.1) failed"]
--- error_log eval
"lua tcp socket bind ip: 127.0.0.1"



=== TEST 2: upstream sockets bind server ip, not 127.0.0.1
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local ip = "$TEST_NGINX_SERVER_IP"
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local bytes, err = sock:send("GET /foo HTTP/1.1\r\nHost: localhost\r\nConnection: keepalive\r\n\r\n")
            if not bytes then
                ngx.say("failed to send request: ", err)
                return
            end

            ngx.say("request sent")

            local reader = sock:receiveuntil("\r\n0\r\n\r\n")
            local data, err = reader()

            if not data then
                ngx.say("failed to receive response body: ", err)
                return
            end

            ngx.say("received response")
            local remote_ip = string.match(data, "(bind: %d+%.%d+%.%d+%.%d+)")
            if remote_ip == "bind: $TEST_NGINX_SERVER_IP" then
                ngx.say("ip matched")
            end

            ngx.say("done")
        }
    }

    location /foo {
        echo bind: $remote_addr;
    }
--- request
GET /t
--- response_body
connected: 1
request sent
received response
ip matched
done
--- no_error_log eval
["[error]",
"bind($ENV{TEST_NGINX_SERVER_IP}) failed"]
--- error_log eval
"lua tcp socket bind ip: $ENV{TEST_NGINX_SERVER_IP}"



=== TEST 3: add setkeepalive
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua;;';"
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local test = require "test"
            local t1 = test.go()
            local t2 = test.go()
            ngx.say("t2 - t1: ", t2 - t1)
        }
    }
--- user_files
>>> test.lua
local _M = {}

function _M.go()
    local ip = "127.0.0.1"
    local port = ngx.var.port

    local sock = ngx.socket.tcp()
    local ok, err = sock:bind(ip)
    if not ok then
        ngx.say("failed to bind", err)
        return
    end

    ngx.say("bind: ", ip)

    local ok, err = sock:connect("127.0.0.1", port)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    ngx.say("connected: ", ok)

    local reused = sock:getreusedtimes()

    local ok, err = sock:setkeepalive()
    if not ok then
        ngx.say("failed to set reusable: ", err)
    end

    return reused
end

return _M
--- request
GET /t
--- response_body
bind: 127.0.0.1
connected: 1
bind: 127.0.0.1
connected: 1
t2 - t1: 1
--- no_error_log
["[error]",
"bind(127.0.0.1) failed"]
--- error_log eval
"lua tcp socket bind ip: 127.0.0.1"



=== TEST 4: upstream sockets bind not exist ip
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local ip = "$TEST_NGINX_NOT_EXIST_IP"
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind", err)
                return
            end

            ngx.say("bind: ", ip)

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        }
    }
--- request
GET /t
--- response_body
bind: 8.8.8.8
failed to connect: cannot assign requested address
--- error_log eval
["bind(8.8.8.8) failed",
"lua tcp socket bind ip: 8.8.8.8"]



=== TEST 5: upstream sockets bind invalid ip
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local ip = "$TEST_NGINX_INVALID_IP"
            local port = ngx.var.port

            local sock = ngx.socket.tcp()
            local ok, err = sock:bind(ip)
            if not ok then
                ngx.say("failed to bind: ", err)
                return
            end

            ngx.say("bind: ", ip)

            local ok, err = sock:connect("127.0.0.1", port)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)
        }
    }
--- request
GET /t
--- response_body
failed to bind: bad address
--- no_error_log
[error]



=== TEST 6: tcpsock across request after bind
--- http_config
    init_worker_by_lua_block {
        -- this is not the recommend way, just for test
        local function tcp()
            local sock = ngx.socket.tcp()

            local ok, err = sock:bind("127.0.0.1")
            if not ok then
                ngx.log(ngx.ERR, "failed to bind")
            end

            package.loaded.share_sock = sock
        end

        local ok, err = ngx.timer.at(0, tcp)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer")
        end
    }
--- config
   server_tokens off;
   location /t {
        set $port $TEST_NGINX_SERVER_PORT;
        content_by_lua_block {
            local port = ngx.var.port

            -- make sure share_sock is created
            ngx.sleep(0.002)

            local sock = package.loaded.share_sock
            if sock ~= nil then
                package.loaded.share_sock = nil

                local ok, err = sock:connect("127.0.0.1", port)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                sock:close()
                collectgarbage("collect")
            else
                -- the sock from package.loaded.share_sock is just
                -- for the first request after worker init
                -- add following code to keep the same result for other request
                ngx.say("connected: ", 1)
            end
        }
    }
--- request
GET /t
--- response_body
connected: 1
--- no_error_log
[error]
