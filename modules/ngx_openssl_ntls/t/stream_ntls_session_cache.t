#!/usr/bin/perl

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2021 Alibaba Group Holding Limited

# Tests for stream ssl module.

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
my $t = Test::Nginx->new()->has(qw/stream stream_ssl/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

stream {
    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    ssl_session_tickets off;

    server {
        listen 127.0.0.1:8080 ssl;

        ssl_session_cache builtin;

        return "body $ssl_session_reused";
    }

    server {
        listen 127.0.0.1:8082 ssl;

        ssl_session_cache off;

        return "body $ssl_session_reused";
    }

    server {
        listen 127.0.0.1:8083 ssl;

        ssl_session_cache builtin:1000;

        return "body $ssl_session_reused";
    }

    server {
        listen 127.0.0.1:8084 ssl;

        ssl_session_cache shared:SSL:1m;

        return "body $ssl_session_reused";
    }
}

EOF

make_sm2_end_certs($t, "server");

my $d = $t->testdir();

$t->run()->plan(8);
###############################################################################
my $ret1 = `$openssl s_client -connect localhost:8080 -quiet -sess_out 1.sess -enable_ntls -ntls 2>&1`;
my $ret2 = `$openssl s_client -connect localhost:8080 -quiet -sess_in 1.sess -enable_ntls -ntls 2>&1`;
my $ret3 = `$openssl s_client -connect localhost:8082 -quiet -sess_out 3.sess -enable_ntls -ntls 2>&1`;
my $ret5 = `$openssl s_client -connect localhost:8083 -quiet -sess_out 5.sess -enable_ntls -ntls 2>&1`;
my $ret6 = `$openssl s_client -connect localhost:8083 -quiet -sess_in 5.sess -enable_ntls -ntls 2>&1`;
my $ret7 = `$openssl s_client -connect localhost:8084 -quiet -sess_out 7.sess -enable_ntls -ntls 2>&1`;
my $ret8 = `$openssl s_client -connect localhost:8084 -quiet -sess_in 7.sess -enable_ntls -ntls 2>&1`;

like($ret1, qr/^body \.$/m, 'builtin initial session');
like($ret2, qr/^body r$/m, 'builtin session reused');
like($ret3, qr/^body .$/m, 'session off initial session');
isnt(-f "$d/3.sess", 1, 'session off no session out');
like($ret5, qr/^body \.$/m, 'builtin size initial session');
like($ret6, qr/^body r$/m, 'builtin size session reused');
like($ret7, qr/^body \.$/m, 'shared initial session');
like($ret8, qr/^body r$/m, 'shared session reused');

###############################################################################
