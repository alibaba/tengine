# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * 43;

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

log_level 'debug';

no_long_string();
#no_diff();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

our $MTLSCA = read_file("t/cert/mtls_ca.crt");
our $MTLSClient = read_file("t/cert/mtls_client.crt");
our $MTLSClientKey = read_file("t/cert/mtls_client.key");
our $MTLSServer = read_file("t/cert/mtls_server.crt");
our $MTLSServerKey = read_file("t/cert/mtls_server.key");

our $HtmlDir = html_dir;

our $mtls_http_config = <<"_EOC_";
server {
    listen unix:$::HtmlDir/mtls.sock ssl;

    ssl_certificate        $::HtmlDir/mtls_server.crt;
    ssl_certificate_key    $::HtmlDir/mtls_server.key;
    ssl_client_certificate $::HtmlDir/mtls_ca.crt;
    ssl_verify_client      on;
    server_tokens          off;

    location / {
        return 200 "hello, \$ssl_client_s_dn";
    }
}
_EOC_

our $mtls_user_files = <<"_EOC_";
>>> mtls_server.key
$::MTLSServerKey
>>> mtls_server.crt
$::MTLSServer
>>> mtls_ca.crt
$::MTLSCA
>>> mtls_client.key
$::MTLSClientKey
>>> mtls_client.crt
$::MTLSClient
_EOC_

run_tests();

__DATA__

=== TEST 1: sanity: www.bing.com
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;

    location /t {
        content_by_lua_block {
            -- avoid flushing bing in "check leak" testing mode:
            local counter = package.loaded.counter
            if not counter then
                counter = 1
            elseif counter >= 2 then
                return ngx.exit(503)
            else
                counter = counter + 1
            end

            package.loaded.counter = counter

            do
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)

                local ok, err = sock:connect("www.bing.com", 443)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake()
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(sess))

                local req = "GET / HTTP/1.1\r\nHost: www.bing.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive response status line: ", err)
                    return
                end

                ngx.say("received: ", line)

                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end  -- do

            collectgarbage()
        }
    }
--- request
GET /t
--- response_body_like chop
\Aconnected: 1
ssl handshake: cdata
sent http request: 57 bytes.
received: HTTP/1.1 (?:200 OK|302 Found)
close: 1 nil
\z
--- grep_error_log eval: qr/lua ssl (?:set|save|free) session: [0-9A-F]+/
--- grep_error_log_out eval
qr/^lua ssl save session: ([0-9A-F]+)
lua ssl free session: ([0-9A-F]+)
$/
--- no_error_log
lua ssl server name:
SSL reused session
[error]
[alert]
--- timeout: 5



=== TEST 2: mutual TLS handshake, upstream is not accessible without client certs
--- http_config eval: $::mtls_http_config
--- config eval
"
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect('unix:$::HtmlDir/mtls.sock')
            if not ok then
                ngx.say('failed to connect: ', err)
            end

            assert(sock:sslhandshake())

            ngx.say('connected: ', ok)

            local req = 'GET /\\r\\n'

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say('failed to send request: ', err)
                return
            end

            ngx.say('request sent: ', bytes)

            ngx.say(sock:receive('*a'))

            assert(sock:close())
        }
    }
"
--- user_files eval: $::mtls_user_files
--- request
GET /t
--- response_body_like: 400 No required SSL certificate was sent
--- no_error_log
[alert]
[error]
[crit]
[emerg]



=== TEST 3: mutual TLS handshake, upstream is accessible with client certs
--- http_config eval: $::mtls_http_config
--- config eval
"
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            local ok, err = sock:connect('unix:$::HtmlDir/mtls.sock')
            if not ok then
                ngx.say('failed to connect: ', err)
            end

            local f = assert(io.open('$::HtmlDir/mtls_client.crt'))
            local cert_data = f:read('*a')
            f:close()

            f = assert(io.open('$::HtmlDir/mtls_client.key'))
            local key_data = f:read('*a')
            f:close()

            local ssl = require('ngx.ssl')

            local chain = assert(ssl.parse_pem_cert(cert_data))
            local priv = assert(ssl.parse_pem_priv_key(key_data))

            sock:setclientcert(chain, priv)

            assert(sock:sslhandshake())

            ngx.say('connected: ', ok)

            local req = 'GET /\\r\\n'

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say('failed to send request: ', err)
                return
            end

            ngx.say('request sent: ', bytes)

            ngx.say(sock:receive('*a'))

            assert(sock:close())
        }
    }
"
--- user_files eval: $::mtls_user_files
--- request
GET /t
--- response_body
connected: 1
request sent: 7
hello, CN=foo@example.com,O=OpenResty,ST=California,C=US
--- no_error_log
[alert]
[error]
[crit]
[emerg]



=== TEST 4: incorrect type of client cert
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            local ok, err = sock:setclientcert("doesnt", "work")
            if not ok then
                ngx.say('failed to setclientcert: ', err)
                return
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
failed to setclientcert: bad cert arg: cdata expected, got string
--- no_error_log
[alert]
[error]
[crit]
[emerg]



=== TEST 5: incorrect type of client key
--- config eval
"
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            local f = assert(io.open('$::HtmlDir/mtls_client.crt'))
            local cert_data = f:read('*a')
            f:close()

            local ssl = require('ngx.ssl')

            local chain = assert(ssl.parse_pem_cert(cert_data))

            local ok, err = sock:setclientcert(chain, 'work')
            if not ok then
                ngx.say('failed to setclientcert: ', err)
                return
            end

            assert(sock:close())
        }
    }
"
--- user_files eval: $::mtls_user_files
--- request
GET /t
--- response_body
failed to setclientcert: bad pkey arg: cdata expected, got string
--- no_error_log
[alert]
[error]
[crit]
[emerg]



=== TEST 6: missing client cert
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            local ok, err = sock:setclientcert(nil, "work")
            if not ok then
                ngx.say('failed to setclientcert: ', err)
                return
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
failed to setclientcert: client certificate must be supplied with corresponding private key
--- no_error_log
[alert]
[error]
[crit]
[emerg]



=== TEST 7: missing private key
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()

            local ok, err = sock:setclientcert('doesnt', nil)
            if not ok then
                ngx.say('failed to setclientcert: ', err)
                return
            end

            assert(sock:close())
        }
    }
--- request
GET /t
--- response_body
failed to setclientcert: client certificate must be supplied with corresponding private key
--- no_error_log
[alert]
[error]
[crit]
[emerg]
