# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

my $pwd = `pwd`;
chomp $pwd;
$ENV{TEST_NGINX_PWD} ||= $pwd;

#master_on();
workers(1);
#log_level('warn');
#worker_connections(1014);
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_package_path '$TEST_NGINX_PWD/t/lib/?.lua;;';
--- config
    location /test {
        content_by_lua '
            package.loaded["socket"] = ngx.socket
            local Memcached = require "Memcached"
            Memcached.socket = ngx.socket

            local memc = Memcached.Connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)

            memc:set("some_key", "hello 1234")
            local data = memc:get("some_key")
            ngx.say("some_key: ", data)
        ';
    }
--- request
    GET /test
--- response_body
some_key: hello 1234
--- no_error_log
[error]



=== TEST 2: raw memcached
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;;';"
--- config
    location /t {
        content_by_lua '
            local memcached = require "resty.memcached"
            local memc, err = memcached.connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)

            local ok, err = memc:set("some_key", "hello 1234")
            if not ok then
                ngx.log(ngx.ERR, "failed to set some_key: ", err)
                ngx.exit(500)
            end

            local data, err = memc:get("some_key")
            if not data and err then
                ngx.log(ngx.ERR, "failed to get some_key: ", err)
                ngx.exit(500)
            end

            ngx.say("some_key: ", data)

            local res, err = memc:set_keepalive()
            if not res then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
    }
--- user_files
>>> resty/memcached.lua
module("resty.memcached", package.seeall)

local mt = { __index = resty.memcached }
local sub = string.sub
local escape_uri = ngx.escape_uri
local socket_connect = ngx.socket.connect
local match = string.match

function connect(...)
    local sock, err = socket_connect(...)
    return setmetatable({ sock = sock }, mt)
end

function get(self, key)
    local cmd = "get " .. escape_uri(key) .. "\r\n"
    local bytes, err = self.sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local line, err = self.sock:receive()
    if line == 'END' then
        return nil, nil
    end

    local flags, len = match(line, [[^VALUE %S+ (%d+) (%d+)]])
    if not flags then
        return nil, "bad response: " .. line
    end

    print("size: ", size, ", flags: ", len)

    local data, err = self.sock:receive(len)
    if not data then
        return nil, err
    end

    line, err = self.sock:receive(2) -- discard the trailing CRLF
    if not line then
        return nil, nil, "failed to receive CRLF: " .. (err or "")
    end

    line, err = self.sock:receive() -- discard "END\r\n"
    if not line then
        return nil, nil, "failed to receive END CRLF: " .. (err or "")
    end

    return data
end

function set(self, key, value, exptime, flags)
    if not exptime then
        exptime = 0
    end

    if not flags then
        flags = 0
    end

    local cmd = table.concat({"set ", escape_uri(key), " ", flags, " ", exptime, " ", #value, "\r\n", value, "\r\n"}, "")

    local bytes, err = self.sock:send(cmd)
    if not bytes then
        return nil, err
    end

    local data, err = self.sock:receive()
    if sub(data, 1, 6) == "STORED" then
        return true
    end

    return false, err
end

function set_keepalive(self)
    return self.sock:setkeepalive(0, 100)
end
--- request
    GET /t
--- response_body
some_key: hello 1234
--- no_error_log
[error]
--- error_log
lua reuse free buf memory
