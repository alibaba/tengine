#!/usr/bin/perl

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2021 Alibaba Group Holding Limited

# Tests for stream ssl module with variables.

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
my $t = Test::Nginx->new()->has(qw/stream stream_ssl sni stream_return/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    server {
        listen  127.0.0.1:8080;
        listen  127.0.0.1:8081 ssl;
        return  $ssl_session_reused:$ssl_session_id:$ssl_cipher:$ssl_protocol;

        ssl_session_cache builtin;
    }

    server {
        listen  127.0.0.1:8082 ssl;
        return  $ssl_server_name;
    }
}

EOF

make_sm2_end_certs($t, "server");

my $d = $t->testdir();


$t->run()->plan(5);

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), ':::', 'no ssl');

my $ret1 = `$openssl s_client -connect localhost:8081 -quiet -sess_out 1.sess -enable_ntls -ntls 2>&1`;
my $ret2 = `$openssl s_client -connect localhost:8081 -quiet -sess_in 1.sess -enable_ntls -ntls 2>&1`;
my $ret3 = `$openssl s_client -connect localhost:8082 -quiet -servername example.com -enable_ntls -ntls 2>&1`;
my $ret4 = `$openssl s_client -connect localhost:8082 -quiet -enable_ntls -ntls 2>/dev/null`;

like($ret1, qr/^\.:(\w{64})?:[\w-]+:NTLSv(\d|\.)+$/m, 'ssl variables');
like($ret2, qr/^r:\w{64}:[\w-]+:NTLSv(\d|\.)+$/m, 'ssl variables - session reused');
like($ret3, qr/^example.com$/m, 'ssl server name');
is($ret4, '', 'ssl server name empty');

###############################################################################
