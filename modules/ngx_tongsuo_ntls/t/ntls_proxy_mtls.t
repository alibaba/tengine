#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# NTLS proxy mutual authentication: a plain frontend proxies to an
# NTLS origin with ssl_verify_client on, presenting its own client
# sign/enc certificates, and verifying the origin certificates against
# the server CA chain.
#
# Note: proxy_ssl_session_reuse is off in every proxied location.  The
# upstream SSL session cache is keyed by peer address only, so the
# three locations sharing https://127.0.0.1:9111 would otherwise reuse
# each other's sessions: an abbreviated handshake resumes the client
# certificate (and the verify result) of whichever location ran first,
# and the negative cases silently pass.
#
# A frontend without client certificates gets a plain 400 from the
# origin: Tongsuo completes the NTLS handshake and nginx rejects the
# request at the HTTP layer ("client sent no required SSL
# certificate"), the same behaviour as in ntls_verify_client.t.  A wrong
# trusted CA fails the post-handshake certificate check in the frontend
# and yields a 502.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use lib ".";
use CA qw/ make_sm2_ca_subca_end_certs /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:9111 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        ssl_verify_client           on;
        ssl_client_certificate      client_ca_chain.crt;

        location / {
            return 200 "proto=$ssl_protocol verify=$ssl_client_verify";
        }
    }

    server {
        listen       127.0.0.1:9115;

        location /ok {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse off;
            proxy_ssl_sign_certificate        client_sign.crt;
            proxy_ssl_sign_certificate_key    client_sign.key;
            proxy_ssl_enc_certificate         client_enc.crt;
            proxy_ssl_enc_certificate_key     client_enc.key;
            proxy_ssl_trusted_certificate     server_ca_chain.crt;
            proxy_ssl_name              server_sign;
            proxy_ssl_verify            on;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9111;
        }

        # no client certificates: the origin completes the NTLS
        # handshake and rejects the request with a plain 400
        location /nocert {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse off;
            proxy_ssl_trusted_certificate     server_ca_chain.crt;
            proxy_ssl_name              server_sign;
            proxy_ssl_verify            on;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9111;
        }

        # wrong CA: the handshake succeeds but the post-handshake
        # certificate check fails and the frontend returns 502
        location /badca {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse off;
            proxy_ssl_sign_certificate        client_sign.crt;
            proxy_ssl_sign_certificate_key    client_sign.key;
            proxy_ssl_enc_certificate         client_enc.crt;
            proxy_ssl_enc_certificate_key     client_enc.key;
            proxy_ssl_trusted_certificate     client_ca_chain.crt;
            proxy_ssl_name              server_sign;
            proxy_ssl_verify            on;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9111;
        }
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "client");
make_sm2_ca_subca_end_certs($t, "server");

$t->run();

###############################################################################

my $r;

$r = http_get('/ok', PeerAddr => '127.0.0.1:9115');
like($r, qr/^proto=NTLSv1\.1\b/m, 'mutual NTLS handshake succeeds');
like($r, qr/verify=SUCCESS\b/, 'origin verifies the proxy client certificates');

$r = http_get('/nocert', PeerAddr => '127.0.0.1:9115');
like($r, qr/^HTTP\/1\.. 400/m, 'origin rejects a request without client certificates');

$r = http_get('/badca', PeerAddr => '127.0.0.1:9115');
like($r, qr/^HTTP\/1\.. 502/m, 'frontend rejects origin certificates from a wrong CA');

$t->stop();

like($t->read_file('error.log'),
    qr/upstream SSL certificate verify error/,
    'wrong trusted CA logged as a certificate verify error');

###############################################################################
