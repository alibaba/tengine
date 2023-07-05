#!/usr/bin/perl

# Copyright (C) Jin Jiu (wa5i)
# Copyright (C) 2022 Alibaba Group Holding Limited

###############################################################################
use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use lib ".";
use CA qw/ make_sm2_ca_subca_end_certs make_rsa_end_cert make_ec_end_cert /;
###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/tongsuo/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(9);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:9022 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_certificate_key ec.key;
        ssl_certificate     ec.crt;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_trusted_certificate     client_ca_chain.crt;

        location / {
            return 200 "ssl_protocol=$ssl_protocol, ssl_cipher=$ssl_cipher";
        }
    }

    server {
        listen       127.0.0.1:9023 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_certificate_key ec.key;
        ssl_certificate     ec.crt;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_trusted_certificate     client_ca_chain.crt;

        location / {
            proxy_enable_ntls $arg_enable_ntls;
            proxy_ssl_sign_certificate        client_sign.crt;
            proxy_ssl_sign_certificate_key    client_sign.key;
            proxy_ssl_enc_certificate         client_enc.crt;
            proxy_ssl_enc_certificate_key     client_enc.key;
            proxy_ssl_trusted_certificate     server_ca_chain.crt;
            proxy_ssl_ciphers "ECC-SM2-WITH-SM4-SM3:ECDHE-SM2-WITH-SM4-SM3:RSA";

            proxy_pass https://localhost:9022;
        }

        location /ecdhe {
            proxy_enable_ntls $arg_enable_ntls;
            proxy_ssl_sign_certificate        client_sign.crt;
            proxy_ssl_sign_certificate_key    client_sign.key;
            proxy_ssl_enc_certificate         client_enc.crt;
            proxy_ssl_enc_certificate_key     client_enc.key;
            proxy_ssl_trusted_certificate     server_ca_chain.crt;
            proxy_ssl_ciphers "ECDHE-SM2-SM4-GCM-SM3:RSA";

            proxy_pass https://localhost:9022;
        }
    }
}

EOF

my $d = $t->testdir();

make_rsa_end_cert($t);
make_ec_end_cert($t);

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $ret1 = `/bin/echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret2 = `/bin/echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret3 = `/bin/echo -e "GET /?enable_ntls=on HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret4 = `/bin/echo -e "GET /?enable_ntls=on HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret5 = `/bin/echo -e "GET /?enable_ntls=off HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECC-SM2-SM4-GCM-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret6 = `/bin/echo -e "GET /?enable_ntls=xxxxx HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECC-SM2-SM4-GCM-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret7 = `/bin/echo -e "GET /ecdhe HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECDHE-SM2-SM4-CBC-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret8 = `/bin/echo -e "GET /ecdhe?enable_ntls=on HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret9 = `/bin/echo -e "GET /ecdhe?enable_ntls=off HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:9023 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;

like($ret1, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(TLSv1.2 AES128-GCM-SHA256)-----> server(no proxy_enable_ntls) -----(TLSv1.3)-----> origin');
like($ret2, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> server(no proxy_enable_ntls) -----(TLSv1.3)-----> origin');
like($ret3, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECC-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 AES128-GCM-SHA256)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> origin');
like($ret4, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECC-SM2-SM4-CBC-SM3/m, 'client -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> origin');
like($ret5, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(NTLSv1.1 ECC-SM2-SM4-GCM-SM3)-----> server(proxy_enable_ntls=off) -----(TLSv1.3)-----> origin');
like($ret6, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(NTLSv1.1 ECC-SM2-SM4-GCM-SM3)-----> server(proxy_enable_ntls=xxxxx) -----(TLSv1.3)-----> origin');
like($ret7, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> server(no proxy_enable_ntls) -----(TLSv1.3)-----> origin');
like($ret8, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECDHE-SM2-SM4-GCM-SM3/m, 'client -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> origin');
like($ret9, qr/^ssl_protocol=TLSv1\.3.*$/m, 'client -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=off) -----(TLSv1.3)-----> origin');

$t->stop();
