# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(3);

# All these tests need to have new openssl
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $openssl_version = eval { `$NginxBinary -V 2>&1` };

if ($openssl_version =~ m/built with OpenSSL (0\S*|1\.0\S*|1\.1\.0\S*)/) {
    plan(skip_all => "too old OpenSSL, need 1.1.1, was $1");
} else {
    plan tests => repeat_each() * (blocks() * 5);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

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

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: handshake, TLSv1.3
--- http_config
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name   test.com;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        server_tokens off;
        location /foo {
            default_type 'text/plain';
            content_by_lua_block { ngx.status = 201 ngx.say("foo") ngx.exit(201) }
        }
    }
--- config
    server_tokens off;
    lua_ssl_trusted_certificate ../html/test.crt;
    lua_ssl_protocols TLSv1.2 TLSv1.3;
    location /t {
        #set $port 5000;
        set $port $TEST_NGINX_MEMCACHED_PORT;

        content_by_lua_block {
            do
                local sock = ngx.socket.tcp()

                sock:settimeout(3000)

                local ok, err = sock:connect("unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                local sess, err = sock:sslhandshake(nil, "test.com", true)
                if not sess then
                    ngx.say("failed to do SSL handshake: ", err)
                else
                    ngx.say("ssl handshake: ", type(sess))
                end
            end  -- do
            collectgarbage()
        }
    }

--- request
GET /t
--- response_body
connected: 1
ssl handshake: userdata

--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"
--- error_log
SSL: TLSv1.3,
--- no_error_log
[error]
[alert]
--- timeout: 5
