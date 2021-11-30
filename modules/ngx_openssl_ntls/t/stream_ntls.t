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
use CA qw/ make_sm2_ca_subca_end_certs make_rsa_end_cert make_ec_end_cert /;
###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

stream {
    server {
        listen       127.0.0.1:8080 ssl;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_certificate_key ec.key;
        ssl_certificate     ec.crt;

        return "body $ssl_protocol";
    }

    server {
        listen       127.0.0.1:8081 ssl;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client           optional_no_ca;

        return "body $ssl_protocol:$ssl_cipher";
    }

    server {
        listen       127.0.0.1:8082 ssl;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_certificate_key ec.key;
        ssl_certificate     ec.crt;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        return "body $ssl_protocol";
    }
}

EOF

my $d = $t->testdir();

make_rsa_end_cert($t);
make_ec_end_cert($t);

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $ret1 = `$openssl s_client -connect localhost:8080 -cipher aRSA -quiet -ign_eof 2>&1`;
my $ret2 = `$openssl s_client -connect localhost:8080 -cipher aECDSA -quiet -ign_eof 2>&1`;
my $ret3 = `$openssl s_client -connect localhost:8081 -cipher ECC-SM2-SM4-CBC-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret4 = `$openssl s_client -connect localhost:8081 -cipher ECC-SM2-SM4-GCM-SM3 -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret5 = `$openssl s_client -connect localhost:8081 -cipher ECDHE-SM2-SM4-CBC-SM3 -quiet -ign_eof  -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret6 = `$openssl s_client -connect localhost:8081 -cipher ECDHE-SM2-SM4-GCM-SM3 -quiet -ign_eof -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret7 = `$openssl s_client -connect localhost:8082 -cipher aRSA -quiet -ign_eof 2>&1`;
my $ret8 = `$openssl s_client -connect localhost:8082 -cipher aECDSA -quiet -ign_eof 2>&1`;

like($ret1, qr/^body TLSv(\d|\.)+/m, 'disable NTLS, TLS handshake success with aRSA');
like($ret2, qr/^body TLSv(\d|\.)+$/m, 'disable NTLS, TLS handshake success with aECDSA');
like($ret3, qr/^body NTLSv(\d|\.)+:ECC-SM2-SM4-CBC-SM3$/m, 'NTLS ECC-SM2-SM4-CBC-SM3 handshake success');
like($ret4, qr/^body NTLSv(\d|\.)+:ECC-SM2-SM4-GCM-SM3$/m, 'NTLS ECC-SM2-SM4-GCM-SM3 handshake success');
like($ret5, qr/^body NTLSv(\d|\.)+:ECDHE-SM2-SM4-CBC-SM3$/m, 'NTLS ECDHE-SM2-SM4-CBC-SM3 handshake success');
like($ret6, qr/^body NTLSv(\d|\.)+:ECDHE-SM2-SM4-GCM-SM3$/m, 'NTLS ECDHE-SM2-SM4-GCM-SM3 handshake success');
like($ret7, qr/^body TLSv(\d|\.)+$/m, 'enable NTLS, TLS handshake success with aRSA');
like($ret8, qr/^body TLSv(\d|\.)+$/m, 'enable NTLS, TLS handshake success with aECDSA');

$t->stop();
