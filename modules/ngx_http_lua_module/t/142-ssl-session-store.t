# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path realpath);
use File::Basename;

repeat_each(3);

plan tests => repeat_each() * (blocks() * 6 - 1);

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_CERT_DIR} ||= dirname(realpath(abs_path(__FILE__)));

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    ssl_session_store_by_lua_block { print("ssl session store by lua is running!") }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]
--- grep_error_log eval: qr/ssl_session_store_by_lua\(nginx.conf:\d+\):.*?,|\bssl session store: connection reusable: \d+|\breusable connection: \d+/
--- grep_error_log_out eval
qr/^reusable connection: 0
ssl session store: connection reusable: 0
ssl_session_store_by_lua\(nginx\.conf:25\):1: ssl session store by lua is running!,
/m,



=== TEST 2: sleep is not allowed
--- http_config
    ssl_session_store_by_lua_block {
        local begin = ngx.now()
        ngx.sleep(0.1)
        print("elapsed in ssl store session by lua: ", ngx.now() - begin)
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"
API disabled in the context of ssl_session_store_by_lua*

--- no_error_log
[alert]
[emerg]



=== TEST 3: timer
--- http_config
    ssl_session_store_by_lua_block {
        local function f()
            print("my timer run!")
        end
        local ok, err = ngx.timer.at(0, f)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
            return
        end
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"
my timer run!

--- no_error_log
[error]
[alert]



=== TEST 4: cosocket is not allowed
--- http_config
    ssl_session_store_by_lua_block {
        local sock = ngx.socket.tcp()

        sock:settimeout(5000)

        local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
        if not ok then
            ngx.log(ngx.ERR, "failed to connect to memc: ", err)
            return
        end

        local bytes, err = sock:send("flush_all\\r\\n")
        if not bytes then
            ngx.log(ngx.ERR, "failed to send flush_all command: ", err)
            return
        end

        local res, err = sock:receive()
        if not res then
            ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
            return
        end

        print("received memc reply: ", res)
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"
API disabled in the context of ssl_session_store_by_lua*

--- no_error_log
[alert]
[emerg]



=== TEST 5: ngx.exit(0) - no yield
--- http_config
    ssl_session_store_by_lua_block {
        ngx.exit(0)
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(package.loaded.session, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                package.loaded.session = sess

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua exit with code 0

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 6: ngx.exit(ngx.ERROR) - no yield
ngx.exit does not yield and the error code is eaten.
--- http_config
    ssl_session_store_by_lua_block {
        ngx.exit(ngx.ERROR)
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(package.loaded.session, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                package.loaded.session = sess

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua exit with code -1
ssl_session_store_by_lua*: handler return value: 0, sess new cb exit code: 0

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 7: lua exception - no yield
--- http_config
    ssl_session_store_by_lua_block {
        error("bad bad bad")
        ngx.log(ngx.ERR, "should never reached here...")
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
failed to run session_store_by_lua*: ssl_session_store_by_lua(nginx.conf:25):2: bad bad bad

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 8: get phase
--- http_config
    ssl_session_store_by_lua_block {
        print("get_phase: ", ngx.get_phase())
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
get_phase: ssl_session_store

--- no_error_log
[alert]
[emerg]
[error]



=== TEST 9: inter-operation with ssl_certificate_by_lua
--- http_config
    ssl_session_store_by_lua_block { print("ssl store session by lua is running!") }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl cert by lua: ", ngx.now() - begin)
        }
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log eval
[
'lua ssl server name: "test.com"',
qr/elapsed in ssl cert by lua: 0.(?:09|1[01])\d+,/,
'ssl_session_store_by_lua(nginx.conf:25):1: ssl store session by lua is running!',
]

--- no_error_log
[error]
[alert]



=== TEST 10: simple logging (by file)
--- http_config
    ssl_session_store_by_lua_file html/a.lua;
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- user_files
>>> a.lua
print("ssl store session by lua is running!")

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"
a.lua:1: ssl store session by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 11: will crash when ssl_session_store_by_lua* is allowed in server context
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name foo.com;
        ssl_session_store_by_lua_block {
            print("handler in test.com")
        }
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;

        server_tokens off;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- no_error_log
[error]
--- must_die
--- error_log eval
qr/\[emerg\] .*? "ssl_session_store_by_lua_block" directive is not allowed here .*?\bnginx\.conf:28/



=== TEST 12: mixing ssl virtual servers with non-ssl virtual servers
--- http_config
    ssl_session_store_by_lua_block { print("ssl session store by lua is running!") }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/https.sock ssl;
        server_name   test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/http.sock;
        server_name   foo.com;

        server_tokens off;
    }
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;

    location /t {
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/https.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil

--- error_log
lua ssl server name: "test.com"
ssl_session_store_by_lua(nginx.conf:25):1: ssl session store by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 13: ssl_session_store_by_lua* is skipped when using TLSv1.3
--- skip_openssl: 6: < 1.1.1
--- http_config
    ssl_session_store_by_lua_block { ngx.log(ngx.ERR, "ssl_session_store_by_lua* is running!") }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
        ssl_certificate_key $TEST_NGINX_CERT_DIR/cert/test.key;
        ssl_session_tickets off;
        ssl_protocols TLSv1.3;
        server_tokens off;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate $TEST_NGINX_CERT_DIR/cert/test.crt;
    lua_ssl_protocols TLSv1.3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(5000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do
            -- collectgarbage()
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
close: 1 nil
--- error_log eval
qr/ssl_session_store_by_lua\*: skipped since TLS version >= 1\.3 \(\d+\)/
--- no_error_log
[error]
[alert]
[emerg]
