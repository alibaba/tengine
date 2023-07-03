# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0|1\.0\.(?:0|1[^\d]|2[a-d]).*)/) {
    plan(skip_all => "too old OpenSSL, need 1.0.2e, was $1");
} else {
    plan tests => repeat_each() * (blocks() * 6 + 4);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: simple logging
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]
--- grep_error_log eval: qr/ssl_certificate_by_lua\(nginx.conf:\d+\):.*?,|\bssl cert: connection reusable: \d+|\breusable connection: \d+/
--- grep_error_log_out eval
# Since nginx version 1.17.9, nginx call ngx_reusable_connection(c, 0)
# before call ssl callback function
$Test::Nginx::Util::NginxVersion >= 1.017009 ?
qr/reusable connection: 0
ssl cert: connection reusable: 0
ssl_certificate_by_lua\(nginx.conf:28\):1: ssl cert by lua is running!,/
: qr /reusable connection: 1
ssl cert: connection reusable: 1
reusable connection: 0
ssl_certificate_by_lua\(nginx.conf:28\):1: ssl cert by lua is running!,/



=== TEST 2: sleep
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl cert by lua: ", ngx.now() - begin)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log eval
[
'lua ssl server name: "test.com"',
qr/elapsed in ssl cert by lua: 0.(?:09|1\d)\d+,/,
]

--- no_error_log
[error]
[alert]



=== TEST 3: timer
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local function f()
                print("my timer run!")
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.log(ngx.ERR, "failed to create timer: ", err)
                return
            end
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
my timer run!

--- no_error_log
[error]
[alert]



=== TEST 4: cosocket
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local sock = ngx.socket.tcp()

            sock:settimeout(2000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to memc: ", err)
                return
            end

            local bytes, err = sock:send("flush_all\r\n")
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
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
received memc reply: OK

--- no_error_log
[error]
[alert]



=== TEST 5: ngx.exit(0) - no yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            ngx.exit(0)
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
lua exit with code 0

--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 6: ngx.exit(ngx.ERROR) - no yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            ngx.exit(ngx.ERROR)
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua_certificate_by_lua: handler return value: -1, cert cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 7: ngx.exit(0) -  yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(0)

            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean

--- error_log
lua exit with code 0

--- no_error_log
should never reached here
[error]
[alert]
[emerg]



=== TEST 8: ngx.exit(ngx.ERROR) - yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            ngx.sleep(0.001)
            ngx.exit(ngx.ERROR)

            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua_certificate_by_lua: cert cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
'lua exit with code -1',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 9: lua exception - no yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_certificate_by_lua(nginx.conf:28):2: bad bad bad',
'lua_certificate_by_lua: handler return value: 500, cert cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
qr/context: ssl_certificate_by_lua\*, client: \d+\.\d+\.\d+\.\d+, server: \d+\.\d+\.\d+\.\d+:\d+/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 10: lua exception - yield
--- http_config
    server {
        listen 127.0.0.2:$TEST_NGINX_RAND_PORT_1 ssl;
        server_name test.com;
        ssl_certificate_by_lua_block {
            ngx.sleep(0.001)
            error("bad bad bad")
            ngx.log(ngx.ERR, "should never reached here...")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.2", $TEST_NGINX_RAND_PORT_1)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'runtime error: ssl_certificate_by_lua(nginx.conf:28):3: bad bad bad',
'lua_certificate_by_lua: cert cb exit code: 0',
qr/\[info\] .*? SSL_do_handshake\(\) failed .*?cert cb error/,
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 11: get phase
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {print("get_phase: ", ngx.get_phase())}
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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
            end
            collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata

--- error_log
lua ssl server name: "test.com"
get_phase: ssl_cert

--- no_error_log
[error]
[alert]



=== TEST 12: connection aborted prematurely
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            ngx.sleep(0.3)
            -- local ssl = require "ngx.ssl"
            -- ssl.clear_certs()
            print("ssl-cert-by-lua: after sleeping")
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(150)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t

--- response_body
connected: 1
failed to do SSL handshake: timeout

--- error_log
lua ssl server name: "test.com"
ssl-cert-by-lua: after sleeping

--- no_error_log
[error]
[alert]
--- wait: 0.6



=== TEST 13: subrequests disabled
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {ngx.location.capture("/foo")}
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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
            end  -- do
            -- collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
failed to do SSL handshake: handshake failed

--- error_log eval
[
'lua ssl server name: "test.com"',
'ssl_certificate_by_lua(nginx.conf:28):1: API disabled in the context of ssl_certificate_by_lua*',
qr/\[info\] .*?cert cb error/,
]

--- no_error_log
[alert]



=== TEST 14: simple logging (by_lua_file)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_file html/a.lua;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block {ngx.status = 201 ngx.say("foo") ngx.exit(201)}
            more_clear_headers Date;
        }
    }

--- user_files
>>> a.lua
print("ssl cert by lua is running!")

--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
a.lua:1: ssl cert by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 15: coroutine API
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            local function f()
                local cnt = 0
                for i = 1, 20 do
                    print("co yield: ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i = 1, 3 do
                print("co resume, status: ", coroutine.status(c))
                cr(c)
            end
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- grep_error_log eval: qr/co (?:yield: \d+|resume, status: \w+)/
--- grep_error_log_out
co resume, status: suspended
co yield: 0
co resume, status: suspended
co yield: 1
co resume, status: suspended
co yield: 2

--- error_log
lua ssl server name: "test.com"

--- no_error_log
[error]
[alert]



=== TEST 16: simple user thread wait with yielding
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            local function f()
                ngx.sleep(0.01)
                print("uthread: hello in thread")
                return "done"
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.log(ngx.ERR, "uthread: failed to spawn thread: ", err)
                return ngx.exit(ngx.ERROR)
            end

            print("uthread: thread created: ", coroutine.status(t))

            local ok, res = ngx.thread.wait(t)
            if not ok then
                print("uthread: failed to wait thread: ", res)
                return
            end

            print("uthread: ", res)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- no_error_log
[error]
[alert]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: thread created: running
uthread: hello in thread
uthread: done



=== TEST 17: simple logging - use ssl_certificate_by_lua* on the http {} level
GitHub openresty/lua-resty-core#42
--- http_config
    ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
    ssl_certificate ../../cert/test.crt;
    ssl_certificate_key ../../cert/test.key;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
lua ssl server name: "test.com"
ssl_certificate_by_lua(nginx.conf:25):1: ssl cert by lua is running!

--- no_error_log
[error]
[alert]



=== TEST 18: simple logging (syslog)
github issue #723
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        error_log syslog:server=127.0.0.1:12345 debug;

        ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log eval
[
qr/\[error\] .*? send\(\) failed/,
'lua ssl server name: "test.com"',
]
--- no_error_log
[alert]
ssl_certificate_by_lua:1: ssl cert by lua is running!



=== TEST 19: check the count of running timers
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /timers {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.timer.at(0.1, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.11, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.09, function() ngx.sleep(0.3) end)
                ngx.sleep(0.2)
                ngx.say(ngx.timer.running_count())
            }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /timers HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 59 bytes.
received: HTTP/1.1 200 OK
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 2
received: Connection: close
received: 
received: 3
close: 1 nil

--- error_log eval
[
'ssl_certificate_by_lua(nginx.conf:29):1: ssl cert by lua is running!',
'lua ssl server name: "test.com"',
]
--- no_error_log
[error]
[alert]



=== TEST 20: some server {} block missing ssl_certificate_by_lua* handlers (literal server name)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /timers {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.timer.at(0.1, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.11, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.09, function() ngx.sleep(0.3) end)
                ngx.sleep(0.2)
                ngx.say(ngx.timer.running_count())
            }
            more_clear_headers Date;
        }
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test2.com;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test2.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /timers HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
failed to do SSL handshake: handshake failed

--- error_log eval
[
qr/\[alert\] .*? no ssl_certificate_by_lua\* defined in server test2\.com\b/,
qr/\[info\] .*? SSL_do_handshake\(\) failed\b/,
]



=== TEST 21: some server {} block missing ssl_certificate_by_lua* handlers (regex server name)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block { print("ssl cert by lua is running!") }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /timers {
            default_type 'text/plain';
            content_by_lua_block {
                ngx.timer.at(0.1, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.11, function() ngx.sleep(0.3) end)
                ngx.timer.at(0.09, function() ngx.sleep(0.3) end)
                ngx.sleep(0.2)
                ngx.say(ngx.timer.running_count())
            }
            more_clear_headers Date;
        }
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name ~test2\.com;
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test2.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET /timers HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
failed to do SSL handshake: handshake failed

--- error_log eval
[
qr/\[alert\] .*? no ssl_certificate_by_lua\* defined in server ~test2\\\.com\b/,
qr/\[info\] .*? SSL_do_handshake\(\) failed\b/,
]



=== TEST 22: get raw_client_addr - IPv4
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    server {
        listen 127.0.0.1:12345 ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            local ssl = require "ngx.ssl"
            local byte = string.byte
            local addr, addrtype, err = ssl.raw_client_addr()
            local ip = string.format("%d.%d.%d.%d", byte(addr, 1), byte(addr, 2),
                       byte(addr, 3), byte(addr, 4))
            print("client ip: ", ip)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("127.0.0.1", 12345)
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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
client ip: 127.0.0.1

--- no_error_log
[error]
[alert]



=== TEST 23: get raw_client_addr - unix domain socket
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;;";

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;

        ssl_certificate_by_lua_block {
            local ssl = require "ngx.ssl"
            local addr, addrtyp, err = ssl.raw_client_addr()
            print("client socket file: ", addr)
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
            more_clear_headers Date;
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    ngx.say("received: ", line)
                end

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
sent http request: 56 bytes.
received: HTTP/1.1 201 Created
received: Server: nginx
received: Content-Type: text/plain
received: Content-Length: 4
received: Connection: close
received: 
received: foo
close: 1 nil

--- error_log
client socket file: 

--- no_error_log
[error]
[alert]



=== TEST 24: ssl_certificate_by_lua* can yield when reading early data
--- skip_openssl: 6: < 1.1.1
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_early_data on;
        server_tokens off;

        ssl_certificate_by_lua_block {
            local begin = ngx.now()
            ngx.sleep(0.1)
            print("elapsed in ssl_certificate_by_lua*: ", ngx.now() - begin)
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(false, nil, true, false)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))
            end  -- do
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: boolean
--- grep_error_log eval
qr/elapsed in ssl_certificate_by_lua\*: 0\.(?:09|1\d)\d+,/,
--- grep_error_log_out eval
[
qr/elapsed in ssl_certificate_by_lua\*: 0\.(?:09|1\d)\d+,/,
qr/elapsed in ssl_certificate_by_lua\*: 0\.(?:09|1\d)\d+,/,
qr/elapsed in ssl_certificate_by_lua\*: 0\.(?:09|1\d)\d+,/,
]
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 25: cosocket (UDP)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_tokens off;

        ssl_certificate_by_lua_block {
            local sock = ngx.socket.udp()

            sock:settimeout(1000)

            local ok, err = sock:setpeername("127.0.0.1", $TEST_NGINX_MEMCACHED_PORT)
            if not ok then
                ngx.log(ngx.ERR, "failed to connect to memc: ", err)
                return
            end

            local req = "\0\1\0\0\0\1\0\0flush_all\r\n"
            local ok, err = sock:send(req)
            if not ok then
                ngx.log(ngx.ERR, "failed to send flush_all to memc: ", err)
                return
            end

            local res, err = sock:receive()
            if not res then
                ngx.log(ngx.ERR, "failed to receive memc reply: ", err)
                return
            end

            ngx.log(ngx.INFO, "received memc reply of ", #res, " bytes")
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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
            end  -- do
            -- collectgarbage()
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
--- no_error_log
[error]
[alert]
[emerg]
--- grep_error_log eval: qr/received memc reply of \d+ bytes/
--- grep_error_log_out eval
[
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
'received memc reply of 12 bytes
',
]



=== TEST 26: uthread (kill)
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        server_tokens off;

        ssl_certificate_by_lua_block {
            local function f()
                ngx.log(ngx.INFO, "uthread: hello from f()")
                ngx.sleep(1)
            end

            local t, err = ngx.thread.spawn(f)
            if not t then
                ngx.log(ngx.ERR, "failed to spawn thread: ", err)
                return ngx.exit(ngx.ERROR)
            end

            local ok, res = ngx.thread.kill(t)
            if not ok then
                ngx.log(ngx.ERR, "failed to kill thread: ", res)
                return
            end

            ngx.log(ngx.INFO, "uthread: killed")

            local ok, err = ngx.thread.kill(t)
            if not ok then
                ngx.log(ngx.INFO, "uthread: failed to kill: ", err)
            end
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../../cert/test.crt;
    lua_ssl_verify_depth 3;

    location /t {
        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(2000)

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
            end  -- do
            -- collectgarbage()
        }
    }
--- request
GET /t
--- response_body
connected: 1
ssl handshake: cdata
--- no_error_log
[error]
[alert]
[emerg]
--- grep_error_log eval: qr/uthread: [^.,]+/
--- grep_error_log_out
uthread: hello from f()
uthread: killed
uthread: failed to kill: already waited or killed
