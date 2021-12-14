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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(6);

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

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  default;

        ssl_session_tickets off;
        ssl_session_cache shared:cache1:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  nocache;

        ssl_session_tickets off;
        ssl_session_cache shared:cache2:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  default;

        ssl_session_ticket_key ticket1.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  tickets;

        ssl_session_ticket_key ticket2.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }
}

EOF

make_sm2_end_certs($t, "server");

$t->write_file('ticket1.key', '1' x 48);
$t->write_file('ticket2.key', '2' x 48);

$t->run();

my $d = $t->testdir();

my $host = "default";
my $ret1 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername $host -quiet -sess_out $d/1.sess -enable_ntls -ntls 2>&1`;
my $ret2 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername $host -quiet -sess_in $d/1.sess -enable_ntls -ntls 2>&1`;
$host = "nocache";
my $ret3 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername $host -quiet -sess_out $d/3.sess -enable_ntls -ntls 2>&1`;
my $ret4 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8080 -servername $host -quiet -sess_in $d/3.sess -enable_ntls -ntls 2>&1`;
$host = "tickets";
my $ret5 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8081 -servername $host -quiet -sess_out $d/5.sess -enable_ntls -ntls 2>&1`;
my $ret6 = `echo -e "GET / HTTP/1.0\r\nHost: $host\r\n\r\n" | $openssl s_client -connect localhost:8081 -servername $host -quiet -sess_in $d/5.sess -enable_ntls -ntls 2>&1`;

like($ret1, qr/^default:\.$/m, 'default server');
like($ret2, qr/^default:r$/m, 'default server reused');
like($ret3, qr/^nocache:\.$/m, 'without cache');
like($ret4, qr/^nocache:r$/m, 'without cache reused');
like($ret5, qr/^tickets:\.$/m, 'tickets');
like($ret6, qr/^tickets:r$/m, 'tickets reused');

$t->stop();
