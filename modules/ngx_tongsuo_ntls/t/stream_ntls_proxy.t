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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl/)->plan(12);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

stream {

    server {
        listen       127.0.0.1:9102 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_certificate_key ec.key;
        ssl_certificate     ec.crt;

        ssl_session_cache off;
        ssl_session_tickets off;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client           optional_no_ca;
        ssl_trusted_certificate     client_ca_chain.crt;

        return "ssl_protocol=$ssl_protocol, ssl_cipher=$ssl_cipher";
    }

    server {
        listen       127.0.0.1:9103 ssl;
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

        ssl_verify_client           optional_no_ca;
        ssl_trusted_certificate     client_ca_chain.crt;

        proxy_ssl on;
        proxy_enable_ntls on;
        proxy_ssl_sign_certificate        client_sign.crt;
        proxy_ssl_sign_certificate_key    client_sign.key;
        proxy_ssl_enc_certificate         client_enc.crt;
        proxy_ssl_enc_certificate_key     client_enc.key;
        proxy_ssl_trusted_certificate     server_ca_chain.crt;
        proxy_ssl_ciphers "ECC-SM2-WITH-SM4-SM3:ECDHE-SM2-WITH-SM4-SM3:RSA";

        proxy_pass localhost:9102;
    }

    server {
        listen       127.0.0.1:9104 ssl;
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

        ssl_verify_client           optional_no_ca;
        ssl_trusted_certificate     client_ca_chain.crt;

        proxy_ssl on;
        proxy_enable_ntls on;
        proxy_ssl_sign_certificate        client_sign.crt;
        proxy_ssl_sign_certificate_key    client_sign.key;
        proxy_ssl_enc_certificate         client_enc.crt;
        proxy_ssl_enc_certificate_key     client_enc.key;
        proxy_ssl_trusted_certificate     server_ca_chain.crt;
        proxy_ssl_ciphers "ECDHE-SM2-SM4-CBC-SM3";

        proxy_pass localhost:9102;
    }

    server {
        listen       127.0.0.1:9105 ssl;
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

        ssl_verify_client           optional_no_ca;
        ssl_trusted_certificate     client_ca_chain.crt;

        proxy_ssl on;
        proxy_enable_ntls off;
        proxy_ssl_sign_certificate        client_sign.crt;
        proxy_ssl_sign_certificate_key    client_sign.key;
        proxy_ssl_enc_certificate         client_enc.crt;
        proxy_ssl_enc_certificate_key     client_enc.key;
        proxy_ssl_trusted_certificate     server_ca_chain.crt;
        proxy_ssl_ciphers "ECC-SM2-SM4-CBC-SM3:ECDHE-SM2-WITH-SM4-SM3:AES128-GCM-SHA256";

        proxy_pass localhost:9102;
    }


    server {
        listen       127.0.0.1:9106 ssl;
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

        ssl_verify_client           optional_no_ca;
        ssl_trusted_certificate     client_ca_chain.crt;

        proxy_ssl on;
        proxy_ssl_ciphers "AES256-GCM-SHA384";

        proxy_pass localhost:9102;
    }
}

EOF

my $d = $t->testdir();

make_rsa_end_cert($t);
make_ec_end_cert($t);

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $ret1 = `$openssl s_client -connect localhost:9103 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret2 = `$openssl s_client -connect localhost:9103 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret3 = `$openssl s_client -connect localhost:9103 -cipher ECDHE-SM2-SM4-CBC-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret4 = `$openssl s_client -connect localhost:9104 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret5 = `$openssl s_client -connect localhost:9104 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret6 = `$openssl s_client -connect localhost:9104 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret7 = `$openssl s_client -connect localhost:9105 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret8 = `$openssl s_client -connect localhost:9105 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret9 = `$openssl s_client -connect localhost:9105 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret10 = `$openssl s_client -connect localhost:9106 -cipher AES128-GCM-SHA256 -quiet -ign_eof 2>&1`;
my $ret11 = `$openssl s_client -connect localhost:9106 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret12 = `$openssl s_client -connect localhost:9106 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;

like($ret1, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECC-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 AES128-GCM-SHA256)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> origin');
like($ret2, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECC-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 ECC-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> origin');
like($ret3, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECC-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 ECDHE-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECC-SM2-SM4-CBC-SM3)-----> origin');

like($ret4, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECDHE-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 AES128-GCM-SHA256)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> origin');
like($ret5, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECDHE-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 ECC-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> origin');
like($ret6, qr/^ssl_protocol=NTLSv1\.1, ssl_cipher=ECDHE-SM2-SM4-CBC-SM3/m, 'client -----(TLSv1.2 ECDHE-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=on) -----(NTLSv1.1 ECDHE-SM2-SM4-CBC-SM3)-----> origin');

like($ret7, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 AES128-GCM-SHA256)-----> server(proxy_enable_ntls=off) -----(TLSv1.3 AES128-GCM-SHA256)-----> origin');
like($ret8, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 ECC-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=off) -----(TLSv1.3 AES128-GCM-SHA256)-----> origin');
like($ret9, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 ECDHE-SM2-SM4-CBC-SM3)-----> server(proxy_enable_ntls=off) -----(TLSv1.3 AES128-GCM-SHA256)-----> origin');

like($ret10, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 AES128-GCM-SHA256)-----> server(no proxy_enable_ntls) -----(TLSv1.3 AES256-GCM-SHA384)-----> origin');
like($ret11, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 ECC-SM2-SM4-CBC-SM3)-----> server(no proxy_enable_ntls) -----(TLSv1.3 AES256-GCM-SHA384)-----> origin');
like($ret12, qr/^ssl_protocol=TLSv1\.3, ssl_cipher=TLS_AES_256_GCM_SHA384/m, 'client -----(TLSv1.3 ECDHE-SM2-SM4-CBC-SM3)-----> server(no proxy_enable_ntls) -----(TLSv1.3 AES256-GCM-SHA384)-----> origin');

$t->stop();
