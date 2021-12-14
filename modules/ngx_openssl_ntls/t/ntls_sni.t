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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(4);

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
        server_name  server1.com;

        enable_ntls  on;
        ssl_sign_certificate        server1_sign.crt;
        ssl_sign_certificate_key    server1_sign.key;
        ssl_enc_certificate         server1_enc.crt;
        ssl_enc_certificate_key     server1_enc.key;

        location / {
            return 200 $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  server2.com;

        enable_ntls  on;
        ssl_sign_certificate        server2_sign.crt;
        ssl_sign_certificate_key    server2_sign.key;
        ssl_enc_certificate         server2_enc.crt;
        ssl_enc_certificate_key     server2_enc.key;

        location / {
            return 200 $server_name;
        }
    }
}

EOF

make_sm2_end_certs($t, "server1");
make_sm2_end_certs($t, "server2");

$t->run();

my $d = $t->testdir();

my $ret1 = `echo Q | $openssl s_client -connect localhost:8080 -noservername -quiet -no_ign_eof -enable_ntls -ntls 2>&1`;
my $ret2 = `echo Q | $openssl s_client -connect localhost:8080 -servername server2.com -quiet -no_ign_eof -enable_ntls -ntls 2>&1`;
my $ret3 = `echo -e "GET / HTTP/1.0\r\nHost: server2.com\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername server2.com -quiet -ign_eof -enable_ntls -ntls 2>&1`;
my $ret4 = `echo -e "GET / HTTP/1.0\r\nHost: server2.com\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername server2.org -quiet -ign_eof -enable_ntls -ntls 2>&1`;

like($ret1, qr/CN = server1_sign$/m, 'default cert');
like($ret2, qr/CN = server2_sign$/m, 'sni cert');
like($ret3, qr/^server2.com$/m,
    'host exists, sni exists, and host is equal sni');
like($ret4, qr/^server2.com$/m, 'host exists, sni not found');

$t->stop();
