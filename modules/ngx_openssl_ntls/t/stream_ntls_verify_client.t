#!/usr/bin/perl

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2021 Alibaba Group Holding Limited

# Tests for stream ssl module, ssl_verify_client.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;
use CA qw/ make_sm2_end_certs /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";
my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
    ->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    log_format  status  $status;

    enable_ntls  on;
    ssl_sign_certificate        1.example.com_sign.crt;
    ssl_sign_certificate_key    1.example.com_sign.key;
    ssl_enc_certificate         1.example.com_enc.crt;
    ssl_enc_certificate_key     1.example.com_enc.key;

    server {
        listen  127.0.0.1:8080;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com_sign_enc.crt;
    }

    server {
        listen  127.0.0.1:8081 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com_sign_enc.crt;

        access_log %%TESTDIR%%/status.log status;
    }

    server {
        listen  127.0.0.1:8082 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com_sign_enc.crt;
        ssl_trusted_certificate 3.example.com_sign_enc.crt;
    }

    server {
        listen  127.0.0.1:8083 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate 2.example.com_sign_enc.crt;
    }
}

EOF

make_sm2_end_certs($t, "1.example.com");
make_sm2_end_certs($t, "2.example.com");
make_sm2_end_certs($t, "3.example.com");

my $d = $t->testdir();

$t->run()->plan(10);

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), ':', 'plain connection');

my $ret1 = `$openssl s_client -connect localhost:8081 -quiet -enable_ntls -ntls 2>/dev/null`;
my $ret2 = `$openssl s_client -connect localhost:8082 -quiet -sign_cert $d/1.example.com_sign.crt -sign_key $d/1.example.com_sign.key -enc_cert $d/1.example.com_enc.crt -enc_key $d/1.example.com_enc.key -enable_ntls -ntls 2>/dev/null`;
my $ret3 = `$openssl s_client -connect localhost:8082 -quiet -enable_ntls -ntls 2>/dev/null`;
my $ret4 = `$openssl s_client -connect localhost:8083 -quiet -sign_cert $d/1.example.com_sign.crt -sign_key $d/1.example.com_sign.key -enc_cert $d/1.example.com_enc.crt -enc_key $d/1.example.com_enc.key -enable_ntls -ntls 2>/dev/null`;
my $ret5 = `$openssl s_client -connect localhost:8081 -quiet -sign_cert $d/2.example.com_sign.crt -sign_key $d/2.example.com_sign.key -enc_cert $d/2.example.com_enc.crt -enc_key $d/2.example.com_enc.key -enable_ntls -ntls 2>/dev/null`;
my $ret6 = `$openssl s_client -connect localhost:8082 -quiet -sign_cert $d/2.example.com_sign.crt -sign_key $d/2.example.com_sign.key -enc_cert $d/2.example.com_enc.crt -enc_key $d/2.example.com_enc.key -enable_ntls -ntls 2>/dev/null`;
my $ret7 = `$openssl s_client -connect localhost:8082 -quiet -sign_cert $d/3.example.com_sign.crt -sign_key $d/3.example.com_sign.key -enc_cert $d/3.example.com_enc.crt -enc_key $d/3.example.com_enc.key -enable_ntls -ntls 2>/dev/null`;
my $ret8 = `$openssl s_client -connect localhost:8082 -quiet -sign_cert $d/3.example.com_sign.crt -sign_key $d/3.example.com_sign.key -enc_cert $d/3.example.com_enc.crt -enc_key $d/3.example.com_enc.key -enable_ntls -ntls -trace 2>/dev/null | grep -A 1 certificate_authorities`;

is($ret1, '', 'no cert');
is($ret2, '', 'bad optional cert');
is($ret3, 'NONE:', 'no optional cert');
like($ret4, qr/^FAILED.*BEGIN/m, 'bad optional_no_ca cert');
like($ret5, qr/^SUCCESS.*BEGIN/m, 'good cert');
like($ret6, qr/^SUCCESS.*BEGIN/m, 'good cert optional');
like($ret7, qr/^SUCCESS.*BEGIN/m, 'good cert trusted');
like($ret8, qr/CN = 2.example.com_sign$/m, 'no trusted sent');

$t->stop();

is($t->read_file('status.log'), "500\n200\n", 'log');

###############################################################################
