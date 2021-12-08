#!/usr/bin/perl

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2021 Alibaba Group Holding Limited

###############################################################################
use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use CA qw/ make_sm2_end_certs /;
###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(9);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_session_cache shared:SSL:1m;
    ssl_session_tickets off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client on;
        ssl_client_certificate      client1_sign_enc.crt;

        location / {
            return 200 "ok";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  on;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client on;
        ssl_client_certificate      client2_sign_enc.crt;

        location / {
            return 200 "$ssl_protocol:$ssl_client_verify";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  optional;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client optional;
        ssl_client_certificate      client2_sign_enc.crt;
        ssl_trusted_certificate     client3_sign_enc.crt;

        location / {
            return 200 "$ssl_protocol:$ssl_client_verify";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  optional_no_ca;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate client2_sign_enc.crt;

        location / {
            return 200 "$ssl_protocol:$ssl_client_verify";
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  no_context;

        ssl_verify_client on;
    }
}

EOF

make_sm2_end_certs($t, "client1");
make_sm2_end_certs($t, "client2");
make_sm2_end_certs($t, "client3");
make_sm2_end_certs($t, "server");

$t->run();

my $d = $t->testdir();

like(http_get('/t'), qr/ok/, 'plain connection');

my $sni = "on";
my $ret1 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -enable_ntls -ntls 2>&1`;
$sni = "no_context";
my $ret2 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -enable_ntls -ntls 2>&1`;
$sni = "optional";
my $ret3 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -enable_ntls -ntls 2>&1`;
my $ret4 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -sign_cert $d/client1_sign.crt -sign_key $d/client1_sign.key -enc_cert $d/client1_enc.crt -enc_key $d/client1_enc.key  -enable_ntls -ntls 2>&1`;
$sni = "optional_no_ca";
my $ret5 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -sign_cert $d/client1_sign.crt -sign_key $d/client1_sign.key -enc_cert $d/client1_enc.crt -enc_key $d/client1_enc.key  -enable_ntls -ntls 2>&1`;
$sni = "localhost";
my $ret6 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -sign_cert $d/client2_sign.crt -sign_key $d/client2_sign.key -enc_cert $d/client2_enc.crt -enc_key $d/client2_enc.key  -enable_ntls -ntls 2>&1`;
$sni = "optional";
my $ret7 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -sign_cert $d/client2_sign.crt -sign_key $d/client2_sign.key -enc_cert $d/client2_enc.crt -enc_key $d/client2_enc.key  -enable_ntls -ntls 2>&1`;
my $ret8 = `echo -e "GET / HTTP/1.0\r\nHost: $sni\r\n" | $openssl s_client -connect localhost:8081 -servername $sni -quiet -sign_cert $d/client3_sign.crt -sign_key $d/client3_sign.key -enc_cert $d/client3_enc.crt -enc_key $d/client3_enc.key  -enable_ntls -ntls 2>&1`;

like($ret1, qr/400 Bad Request/, 'no client cert');
like($ret2, qr/400 Bad Request/, 'no server cert');
like($ret3, qr/^NTLSv(\d|\.)+:NONE$/m, 'no optional cert');
like($ret4, qr/400 Bad Request/, 'bad optional cert');
like($ret5, qr/^NTLSv(\d|\.)+:FAILED/m, 'bad optional_no_ca cert');
like($ret6, qr/^NTLSv(\d|\.)+:SUCCESS$/m, 'good cert');
like($ret7, qr/^NTLSv(\d|\.)+:SUCCESS$/m, 'good cert optional');
like($ret8, qr/^NTLSv(\d|\.)+:SUCCESS$/m, 'good cert trusted');

$t->stop();
