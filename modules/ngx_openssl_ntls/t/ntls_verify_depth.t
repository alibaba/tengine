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
use CA qw/ make_sm2_end_certs make_sm2_ca_subca_end_certs /;
###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    enable_ntls on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    ssl_verify_client on;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_verify_depth 0;
        ssl_client_certificate client1_sign_enc.crt;

        location / {
            return 200 "$ssl_protocol:$ssl_client_verify";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_verify_depth 0;
        ssl_client_certificate client2_ca_chain.crt;
    }
}

EOF

make_sm2_end_certs($t, "client1");
make_sm2_ca_subca_end_certs($t, "client2");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $d = $t->testdir();

my $ret1 = `echo -e "GET /t HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8080 -sign_cert $d/client1_sign.crt -sign_key $d/client1_sign.key -enc_cert $d/client1_enc.crt -enc_key $d/client1_enc.key -quiet -enable_ntls -ntls 2>&1`;
my $ret2 = `echo -e "GET /t HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8081 -sign_cert $d/client2_sign.crt -sign_key $d/client2_sign.key -enc_cert $d/client2_enc.crt -enc_key $d/client2_enc.key -quiet -enable_ntls -ntls 2>&1`;

like($ret1, qr/^NTLSv(\d|\.)+:SUCCESS$/m, 'NTLS verify depth');
like($ret2, qr/400 Bad Request/, 'NTLS verify depth limited');

$t->stop();
