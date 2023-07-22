# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 14);

our $HtmlDir = html_dir;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

no_long_string();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $TestCertificate = read_file("t/cert/test.crt");
our $TestCertificateKey = read_file("t/cert/test.key");

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->error_log) {
        $block->set_value("no_error_log", "[error]");
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }

});

run_tests();

__DATA__

=== TEST 1: set_by_lua
--- config
    location /t {
        set_by_lua_block $res {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            return foo
        }
        echo $res;
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|set_by_lua\(nginx.conf:\d+\):\d+: in main chunk, )/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
set_by_lua\(nginx.conf:40\):3: in main chunk, \n\z/, "old foo: 1\n"]



=== TEST 2: rewrite_by_lua
--- config
    location /t {
        rewrite_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(.*?\):\d+: in main chunk, )/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
rewrite_by_lua\(nginx\.conf:\d+\):\d+: in main chunk, \n\z/, "old foo: 1\n"]



=== TEST 3: access_by_lua
--- config
    location /t {
        access_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(.*?\):\d+: in main chunk, )/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
access_by_lua\(nginx\.conf:\d+\):\d+: in main chunk, \n\z/, "old foo: 1\n"]



=== TEST 4: content_by_lua
--- config
    location /t {
        content_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(.*?\):\d+: in main chunk, )/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
content_by_lua\(nginx\.conf:\d+\):\d+: in main chunk, \n\z/, "old foo: 1\n"]



=== TEST 5: header_filter_by_lua
--- config
    location /t {
        content_by_lua_block {
            ngx.say(foo)
        }
        header_filter_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
        }
    }
--- response_body_like chomp
\A(?:nil|1)\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(nginx\.conf:\d+\):\d+: in main chunk, )/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
header_filter_by_lua\(nginx.conf:43\):3: in main chunk, \n\z/, "old foo: 1\n"]



=== TEST 6: body_filter_by_lua
--- config
    location /t {
        content_by_lua_block {
            ngx.say(foo)
        }
        body_filter_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
        }
    }
--- response_body_like chomp
\A(?:nil|2)\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(nginx\.conf:\d+\):\d+: in main chunk,)/
--- grep_error_log_out eval
[qr/\[warn\] .*?writing a global Lua variable \('foo'\)
body_filter_by_lua\(nginx.conf:43\):3: in main chunk,
old foo: 1\n\z/, "old foo: 2\nold foo: 3\n"]



=== TEST 7: log_by_lua
--- config
    location /t {
        content_by_lua_block {
            ngx.say(foo)
        }
        log_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
        }
    }
--- response_body_like chomp
\A(?:nil|1)\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(.*?\):\d+: in main chunk)/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
log_by_lua\(nginx\.conf:\d+\):\d+: in main chunk\n\z/, "old foo: 1\n"]



=== TEST 8: ssl_certificate_by_lua
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
        }
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;

        server_tokens off;
        location /foo {
            content_by_lua_block {
                ngx.say("foo: ", foo)
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

                -- ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                -- ngx.say("ssl handshake: ", type(sess))

                local req = "GET /foo HTTP/1.0\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                -- ngx.say("sent http request: ", bytes, " bytes.")

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

--- response_body_like chomp
\A[12]done\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(nginx.conf:\d+\):\d+: in main chunk)/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
ssl_certificate_by_lua\(nginx.conf:28\):3: in main chunk\n\z/, "old foo: 1\n"]



=== TEST 9: timer
--- config
    location /t {
        content_by_lua_block {
            local function f()
                if not foo then
                    foo = 1
                else
                    ngx.log(ngx.WARN, "old foo: ", foo)
                    foo = foo + 1
                end
            end
            local ok, err = ngx.timer.at(0, f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.sleep(0.01)
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|\[\w+\].*?writing a global Lua variable \('[^'\s]+'\)|\w+_by_lua\(.*?\):\d+: in\b)/
--- grep_error_log_out eval
[qr/\A\[warn\] .*?writing a global Lua variable \('foo'\)
content_by_lua\(nginx\.conf:\d+\):\d+: in\n\z/, "old foo: 1\n"]



=== TEST 10: init_by_lua
--- http_config
    init_by_lua_block {
        foo = 1
    }
--- config
    location /t {
        content_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[23]\n\z
--- grep_error_log eval: qr/old foo: \d+/
--- grep_error_log_out eval
["old foo: 1\n", "old foo: 2\n"]



=== TEST 11: init_worker_by_lua
--- http_config
    init_worker_by_lua_block {
        if not foo then
            foo = 1
        else
            ngx.log(ngx.WARN, "old foo: ", foo)
            foo = foo + 1
        end
    }
--- config
    location /t {
        content_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[23]\n\z
--- grep_error_log eval: qr/old foo: \d+/
--- grep_error_log_out eval
["old foo: 1\n", "old foo: 2\n"]



=== TEST 12: init_by_lua + init_worker_by_lua
--- http_config
    init_by_lua_block {
        if not foo then
            foo = 1
        else
            ngx.log(ngx.WARN, "old foo: ", foo)
            foo = foo + 1
        end
    }
    init_worker_by_lua_block {
        if not foo then
            foo = 1
        else
            ngx.log(ngx.WARN, "old foo: ", foo)
            foo = foo + 1
        end
    }
--- config
    location /t {
        content_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[34]\n\z
--- grep_error_log eval: qr/old foo: \d+/
--- grep_error_log_out eval
["old foo: 1\nold foo: 2\n", "old foo: 3\n"]



=== TEST 13: don't show warn messages in init/init_worker
--- http_config
    init_by_lua_block {
        foo = 1
    }

    init_worker_by_lua_block {
        bar = 2
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say(foo)
            ngx.say(bar)
        }
    }
--- response_body
1
2
--- no_error_log
setting global variable



=== TEST 14: uthread
--- config
    location /t {
        content_by_lua_block {
            local function f()
                if not foo then
                    foo = 1
                else
                    ngx.log(ngx.WARN, "old foo: ", foo)
                    foo = foo + 1
                end
            end
            local ok, err = ngx.thread.spawn(f)
            if not ok then
                ngx.say("failed to set timer: ", err)
                return
            end
            ngx.sleep(0.01)
            ngx.say(foo)
        }
    }
--- response_body_like chomp
\A[12]\n\z
--- grep_error_log eval
qr/(old foo: \d+|writing a global Lua variable \('\w+'\))/
--- grep_error_log_out eval
["writing a global Lua variable \('foo'\)\n", "old foo: 1\n"]



=== TEST 15: balancer_by_lua
--- http_config
    upstream backend {
        server 0.0.0.1;
        balancer_by_lua_block {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.WARN, "old foo: ", foo)
                foo = foo + 1
            end
        }
    }
--- config
    location = /t {
        proxy_pass http://backend;
    }
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log eval
qr/\[crit\].*?\Qconnect() to 0.0.0.1:80 failed\E/
--- grep_error_log eval: qr/(old foo: \d+|writing a global Lua variable \('\w+'\))/
--- grep_error_log_out eval
["writing a global Lua variable \('foo'\)\n", "old foo: 1\n"]
