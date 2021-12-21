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
use CA qw/ make_sm2_ca_subca_end_certs /;
###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        location / {
            return 200 "$ssl_protocol\n$ssl_cipher";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign_subca.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        location / {
            return 200 "body $ssl_protocol";
        }
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign_allca.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        location / {
            return 200 "body $ssl_protocol";
        }
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->write_file('server_sign_subca.crt',
    $t->read_file('server_sign.crt')
        . $t->read_file('server_subca.crt'));

$t->write_file('server_sign_allca.crt',
    $t->read_file('server_sign.crt')
        . $t->read_file('server_subca.crt')
        . $t->read_file('server_ca.crt'));

$t->run();

my $d = $t->testdir();

my $ret1 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8080 -verify_return_error -quiet -enable_ntls -ntls 2>&1`;
my $ret2 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8081 -CAfile $d/server_ca.crt -verify_return_error -quiet -enable_ntls -ntls 2>&1`;
my $ret3 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8082 -CAfile $d/server_ca.crt -verify_return_error -quiet -enable_ntls -ntls 2>&1`;

like($ret1, qr/^verify error/m, 'NTLS handshake no issuer certificate');
like($ret2, qr/^body NTLSv(\d|\.)+$/m, 'NTLS handshake success with subca');
like($ret3, qr/^body NTLSv(\d|\.)+$/m, 'NTLS handshake success with all ca');

$t->stop();
