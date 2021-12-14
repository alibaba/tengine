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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(11);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    ssl_session_tickets off;

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        # Special case for enabled "ssl" directive.

        ssl on;
        ssl_session_cache builtin;
        ssl_session_timeout 1;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_session_cache builtin:1000;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8083 ssl;
        server_name  localhost;

        ssl_session_cache none;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8084 ssl;
        server_name  localhost;

        ssl_session_cache off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8085 ssl;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_verify_client optional_no_ca;

        location /reuse {
            return 200 "body $ssl_session_reused";
        }
    }
}

EOF

my $d = $t->testdir();

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $ret1 = `echo -e "GET /reuse HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8085 -quiet -sess_out 1.sess -enable_ntls -ntls 2>&1`;
my $ret2 = `echo -e "GET /reuse HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8085 -quiet -sess_in 1.sess -enable_ntls -ntls 2>&1`;
my $ret3 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8081 -quiet -sess_out 3.sess -enable_ntls -ntls 2>&1`;
my $ret4 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8081 -quiet -sess_in 3.sess -enable_ntls -ntls 2>&1`;
my $ret5 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8082 -quiet -sess_out 5.sess -enable_ntls -ntls 2>&1`;
my $ret6 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8082 -quiet -sess_in 5.sess -enable_ntls -ntls 2>&1`;
my $ret7 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8083 -quiet -sess_out 7.sess -enable_ntls -ntls 2>&1`;
my $ret8 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8083 -quiet -sess_in 7.sess -enable_ntls -ntls 2>&1`;
my $ret9 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8084 -quiet -sess_out 9.sess -enable_ntls -ntls 2>&1`;

# session timeout
select undef, undef, undef, 2.1;
my $ret11 = `echo -e "GET / HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:8081 -quiet -sess_in 3.sess -enable_ntls -ntls 2>&1`;

like($ret1, qr/^body \.$/m, 'shared initial session');
like($ret2, qr/^body r$/m, 'shared session reused');
like($ret3, qr/^body \.$/m, 'builtin initial session');
like($ret4, qr/^body r$/m, 'builtin session reused');
like($ret5, qr/^body \.$/m, 'builtin size initial session');
like($ret6, qr/^body r$/m, 'builtin size session reused');
like($ret7, qr/^body \.$/m, 'reused none initial session');
like($ret8, qr/^body \.$/m, 'session not reused 1');
like($ret9, qr/^body \.$/m, 'session off initial session');
isnt(-f "$d/9.sess", 1, 'session off no session out');
like($ret11, qr/^body \.$/m, 'session timeout');

$t->stop();
