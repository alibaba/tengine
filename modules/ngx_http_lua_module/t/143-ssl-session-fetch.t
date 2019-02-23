# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path realpath);
use File::Basename;

repeat_each(3);

plan tests => repeat_each() * (blocks() * 6);

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
    ssl_session_fetch_by_lua_block { print("ssl fetch sess by lua is running!") }
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval: qr/ssl_session_fetch_by_lua_block:.*?,|\bssl session fetch: connection reusable: \d+|\breusable connection: \d+/

--- grep_error_log_out eval
[
qr/\A(?:reusable connection: [01]\n)+\z/s,
qr/^reusable connection: 1
ssl session fetch: connection reusable: 1
reusable connection: 0
ssl_session_fetch_by_lua_block:1: ssl fetch sess by lua is running!,
/m,
qr/^reusable connection: 1
ssl session fetch: connection reusable: 1
reusable connection: 0
ssl_session_fetch_by_lua_block:1: ssl fetch sess by lua is running!,
/m,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 2: sleep
--- http_config
    ssl_session_fetch_by_lua_block {
        local begin = ngx.now()
        ngx.sleep(0.1)
        print("elapsed in ssl fetch session by lua: ", ngx.now() - begin)
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/elapsed in ssl fetch session by lua: 0.(?:09|1[01])\d+,/,

--- grep_error_log_out eval
[
'',
qr/elapsed in ssl fetch session by lua: 0.(?:09|1[01])\d+,/,
qr/elapsed in ssl fetch session by lua: 0.(?:09|1[01])\d+,/,
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 3: timer
--- http_config
    ssl_session_fetch_by_lua_block {
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/my timer run!/s

--- grep_error_log_out eval
[
'',
'my timer run!
',
'my timer run!
',
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 4: cosocket
--- http_config
    ssl_session_fetch_by_lua_block {
        local sock = ngx.socket.tcp()

        sock:settimeout(5000)

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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/received memc reply: OK/s

--- grep_error_log_out eval
[
'',
'received memc reply: OK
',
'received memc reply: OK
',
]

--- no_error_log
[alert]
[error]
[emerg]



=== TEST 5: ngx.exit(0) - yield
--- http_config
    ssl_session_fetch_by_lua_block {
        ngx.exit(0)
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/lua exit with code 0/s

--- grep_error_log_out eval
[
'',
'lua exit with code 0
',
'lua exit with code 0
',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 6: ngx.exit(ngx.ERROR) - yield
--- http_config
    ssl_session_fetch_by_lua_block {
        ngx.exit(ngx.ERROR)
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl_session_fetch_by_lua\*: handler return value: -1, sess get cb exit code: 0/s

--- grep_error_log_out eval
[
'',
'ssl_session_fetch_by_lua*: handler return value: -1, sess get cb exit code: 0
',
'ssl_session_fetch_by_lua*: handler return value: -1, sess get cb exit code: 0
',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 7: ngx.exit(ngx.ERROR) - yield
--- http_config
    ssl_session_fetch_by_lua_block {
        ngx.sleep(0.001)
        ngx.exit(ngx.ERROR)
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl_session_fetch_by_lua\*: sess get cb exit code: 0/s

--- grep_error_log_out eval
[
'',
'ssl_session_fetch_by_lua*: sess get cb exit code: 0
',
'ssl_session_fetch_by_lua*: sess get cb exit code: 0
',
]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 8: lua exception - no yield
--- http_config
    ssl_session_fetch_by_lua_block {
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl_session_fetch_by_lua_block:2: bad bad bad/s

--- grep_error_log_out eval
[
'',
'ssl_session_fetch_by_lua_block:2: bad bad bad
',
'ssl_session_fetch_by_lua_block:2: bad bad bad
',

]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 9: lua exception - yield
--- http_config
    ssl_session_fetch_by_lua_block {
        ngx.sleep(0.001)
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl_session_fetch_by_lua_block:3: bad bad bad|ssl_session_fetch_by_lua\*: sess get cb exit code: 0/s

--- grep_error_log_out eval
[
'',
'ssl_session_fetch_by_lua_block:3: bad bad bad
ssl_session_fetch_by_lua*: sess get cb exit code: 0
',
'ssl_session_fetch_by_lua_block:3: bad bad bad
ssl_session_fetch_by_lua*: sess get cb exit code: 0
',

]

--- no_error_log
should never reached here
[alert]
[emerg]



=== TEST 10: get phase
--- http_config
    ssl_session_fetch_by_lua_block { print("get_phase: ", ngx.get_phase()) }
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/get_phase: ssl_session_fetch/s

--- grep_error_log_out eval
[
'',
'get_phase: ssl_session_fetch
',
'get_phase: ssl_session_fetch
',
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 11: inter-operation with ssl_certificate_by_lua
--- http_config
    ssl_session_store_by_lua_block { print("ssl store session by lua is running!") }
    ssl_session_fetch_by_lua_block {
        ngx.sleep(0.1)
        print("ssl fetch session by lua is running!")
    }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            ngx.sleep(0.1)
            print("ssl cert by lua is running!")
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl ((fetch|store) session|cert) by lua is running!/s

--- grep_error_log_out eval
[
'ssl cert by lua is running!
ssl store session by lua is running!
',
'ssl fetch session by lua is running!
ssl cert by lua is running!
ssl store session by lua is running!
',
'ssl fetch session by lua is running!
ssl cert by lua is running!
ssl store session by lua is running!
',
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 12: simple logging (by file)
--- http_config
    ssl_session_fetch_by_lua_file html/a.lua;
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

--- user_files
>>> a.lua
print("ssl fetch sess by lua is running!")

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/\S+:\d+: ssl fetch sess by lua is running!/s

--- grep_error_log_out eval
[
'',
'a.lua:1: ssl fetch sess by lua is running!
',
'a.lua:1: ssl fetch sess by lua is running!
',
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 13: mixing ssl virtual servers with non-ssl virtual servers
--- http_config
    ssl_session_fetch_by_lua_block { print("ssl fetch sess by lua is running!") }
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
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
ssl handshake: userdata
close: 1 nil

--- grep_error_log eval
qr/ssl_session_fetch_by_lua_block:1: ssl fetch sess by lua is running!/s

--- grep_error_log_out eval
[
'',
'ssl_session_fetch_by_lua_block:1: ssl fetch sess by lua is running!
',
'ssl_session_fetch_by_lua_block:1: ssl fetch sess by lua is running!
',
]

--- no_error_log
[error]
[alert]
[emerg]



=== TEST 14: keep global variable in ssl_session_(store|fetch)_by_lua when OpenResty LuaJIT is used
--- http_config
    ssl_session_store_by_lua_block {
        ngx.log(ngx.WARN, "new foo: ", foo)
        if not foo then
            foo = 1
        else
            ngx.log(ngx.WARN, "old foo: ", foo)
            foo = foo + 1
        end
    }
    ssl_session_fetch_by_lua_block {
        ngx.log(ngx.WARN, "new bar: ", foo)
        if not bar then
            bar = 1
        else
            ngx.log(ngx.WARN, "old bar: ", bar)
            bar = bar + 1
        end
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        ssl_session_tickets off;

        server_tokens off;
        location /foo {
            content_by_lua_block {
                ngx.say("foo: ", foo)
                ngx.say("bar: ", bar)
            }
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

                local sess, err = sock:sslhandshake(package.loaded.session, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                package.loaded.session = sess

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                while true do
                    local line, err = sock:receive()
                    if not line then
                        -- ngx.say("failed to receive response status line: ", err)
                        break
                    end

                    local m, err = ngx.re.match(line, "^foo: (.*)$", "jo")
                    if err then
                        ngx.say("failed to match line: ", err)
                    end

                    if m and m[1] then
                        ngx.print(m[1])
                    end
                end

                local ok, err = sock:close()
                ngx.say("done")
            end  -- do
        }
    }

--- request
GET /t
--- response_body_like chomp
\A[123]done\n\z
--- grep_error_log eval: qr/old (foo|bar): \d+/
--- grep_error_log_out eval
["", "old foo: 1\n", "old bar: 1\nold foo: 2\n"]
--- no_error_log
[error]
[alert]
[emerg]
