#!/usr/bin/perl

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2019 Alibaba Group Holding Limited

# Stream tests for SNI.

###############################################################################
# "For using stream_sni.t, you should configure Tengine by using --with-stream_ssl_module --with-stream_sni";
use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;
use CA qw/ make_sm2_end_certs /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/babassl/bin/openssl";
my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return stream_sni/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse on;
    proxy_connect_timeout 2s;

    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    server {
        listen      127.0.0.1:8081 ssl;
        server_name www.test1.com;

        return "www.test1.com";
    }

    server {
        listen      127.0.0.1:8081 ssl;
        server_name www.test2.com;

        return "www.test2.com";
    }

    server {
        listen      127.0.0.1:8081 ssl default;

        return "default";
    }

    server {
        listen      127.0.0.1:8082 ssl;
        server_name www.testsniforce.com;
        ssl_sni_force on;

        return "www.testsniforce.com";
    }
}

EOF


make_sm2_end_certs($t, "server");

my $d = $t->testdir();

$t->run()->plan(5);
my $ret1 = `$openssl s_client -connect localhost:8081 -quiet -servername "www.test1.com" -enable_ntls -ntls 2>&1 | grep "test1"`;
my $ret2 = `$openssl s_client -connect localhost:8081 -quiet -servername "www.test2.com" -enable_ntls -ntls 2>&1 | grep "test2"`;
my $ret3 = `$openssl s_client -connect localhost:8081 -quiet -servername "www.test3.com" -enable_ntls -ntls 2>&1 | grep "default"`;
my $ret4 = `$openssl s_client -connect localhost:8082 -quiet -servername "www.testsniforce.com" -enable_ntls -ntls 2>&1 | grep "force"`;
my $ret5 = `$openssl s_client -connect localhost:8082 -quiet -servername "www.testother.com" -enable_ntls -ntls 2>&1 | grep "force"`;

like($ret1, qr/www.test1.com/, 'Match www.test1.com success');
like($ret2, qr/www.test2.com/, 'Match www.test2.com success');
like($ret3, qr/default/, 'Match default success');
like($ret4, qr/www.testsniforce.com/, 'sni force success');
unlike($ret5, qr/www.testsniforce.com/, 'reject unknown domain success');

$t->stop();
