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
        listen       127.0.0.1:1443 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_session_tickets off;
        ssl_session_cache shared:SSL:1m;
        ssl_verify_client optional_no_ca;

        location /reuse {
            return 200 "body $ssl_session_reused";
        }
        location /id {
            return 200 "body $ssl_session_id";
        }
        location /cipher {
            return 200 "body $ssl_cipher";
        }

        location /ciphers {
            return 200 "body $ssl_ciphers";
        }

        location /client_verify {
            return 200 "body $ssl_client_verify";
        }

        location /protocol {
            return 200 "body $ssl_protocol";
        }

        location /issuer {
            return 200 "body $ssl_client_i_dn:$ssl_client_i_dn_legacy";
        }
        location /subject {
            return 200 "body $ssl_client_s_dn:$ssl_client_s_dn_legacy";
        }
        location /time {
            return 200 "body $ssl_client_v_start!$ssl_client_v_end!$ssl_client_v_remain";
        }

        location /body {
            add_header X-Body $request_body always;
            proxy_pass http://127.0.0.1:8080/;
        }
    }
}

EOF

my $d = $t->testdir();

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

my $ret1 = `echo -e "GET /id HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enable_ntls -ntls 2>&1`;
my $ret2 = http_get('/id');
my $ret3 = `echo -e "GET /cipher HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enable_ntls -ntls 2>&1`;
my $ret4 = `echo -e "GET /ciphers HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enable_ntls -ntls 2>&1`;
my $ret5 = `echo -e "GET /client_verify HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enable_ntls -ntls 2>&1`;
my $ret6 = `echo -e "GET /protocol HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enable_ntls -ntls 2>&1`;
my $ret7 = `echo -e "GET /issuer HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret8 = `echo -e "GET /subject HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;
my $ret9 = `echo -e "GET /time HTTP/1.0\r\n\r\n" | $openssl s_client -connect localhost:1443 -quiet -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key -enable_ntls -ntls 2>&1`;

like($ret1, qr/^body \w{64}$/m, 'session id');
unlike($ret2, qr/body \w/, 'session id no ssl');
like($ret3, qr/^body [\w-]+$/m, 'cipher');
like($ret4, qr/^body [:\w-]+$/m, 'ciphers');
like($ret5, qr/^body NONE$/m, 'client verify');
like($ret6, qr/^body (NTLS)v(\d|\.)+$/m, 'protocol');
like($ret7, qr!^body CN=client_sub_ca:/CN=client_sub_ca!m, 'issuer');
like($ret8, qr!^body CN=client_sign:/CN=client_sign!m, 'subject');
like($ret9, qr/^body [:\s\w]+![:\s\w]+![23]$/m, 'time');

$t->stop();
