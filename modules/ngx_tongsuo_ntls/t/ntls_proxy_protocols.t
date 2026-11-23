#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Orthogonality of proxy_enable_ntls and proxy_ssl_protocols: the NTLS
# switch and the protocol version list govern independent things.
#
#   - with proxy_enable_ntls on, the upstream context is pinned to
#     NTLS_method(), so the version list never applies to the NTLS
#     handshake: a TLSv1.2-only list still talks NTLS to an NTLS origin;
#
#   - with proxy_enable_ntls off, the connection falls back to the TLS
#     method and the version list applies as usual: a TLSv1.2-only list
#     cannot talk to a TLSv1.3-only origin, while a TLSv1.3 list can.
#
# Together these pin down "the switch governs NTLS, the version list
# governs TLS", which is the semantics enable_ntls was designed for.
#
# The /tls-switch and /ntls-switch cases are supplementary: on their own
# a 502 cannot tell "pinned to NTLS" from a version or cipher mismatch,
# so they rely on the differential cases /ntls and /tls-list-blocked vs
# /tls-list-allowed.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use lib ".";
use CA qw/ make_sm2_ca_subca_end_certs make_rsa_end_cert /;

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

    # NTLS-only origin
    server {
        listen       127.0.0.1:9116 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;

        location / {
            return 200 "proto=$ssl_protocol";
        }
    }

    # TLSv1.3-only origin
    server {
        listen       127.0.0.1:9117 ssl;
        server_name  localhost;

        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;

        ssl_protocols      TLSv1.3;

        location / {
            return 200 "proto=$ssl_protocol";
        }
    }

    server {
        listen       127.0.0.1:9118;

        # NTLS with a TLSv1.2-only version list: the list must not
        # affect the NTLS handshake
        location /ntls {
            proxy_enable_ntls           on;
            proxy_ssl_protocols         TLSv1.2;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9116;
        }

        # NTLS switch on against a TLSv1.3-only origin: the context is
        # pinned to NTLS and never falls back to TLSv1.3
        location /tls-switch {
            proxy_enable_ntls           on;
            proxy_ssl_protocols         TLSv1.2;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9117;
        }

        # NTLS switch off: the version list applies as usual
        location /tls-list-blocked {
            proxy_enable_ntls           off;
            proxy_ssl_protocols         TLSv1.2;

            proxy_pass https://127.0.0.1:9117;
        }

        location /tls-list-allowed {
            proxy_enable_ntls           off;
            proxy_ssl_protocols         TLSv1.3;

            proxy_pass https://127.0.0.1:9117;
        }

        # NTLS switch off against an NTLS-only origin
        location /ntls-switch {
            proxy_enable_ntls           off;
            proxy_ssl_protocols         TLSv1.3;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9116;
        }
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "server");
make_rsa_end_cert($t);

$t->run();

###############################################################################

my $r;

$r = http_get('/ntls', PeerAddr => '127.0.0.1:9118');
like($r, qr/^proto=NTLSv1\.1$/m,
    'proxy_ssl_protocols TLSv1.2 does not affect the NTLS handshake');

$r = http_get('/tls-switch', PeerAddr => '127.0.0.1:9118');
like($r, qr/^HTTP\/1\.. 502/m,
    'proxy_enable_ntls on pins the context to NTLS against a TLS origin');

$r = http_get('/tls-list-blocked', PeerAddr => '127.0.0.1:9118');
like($r, qr/^HTTP\/1\.. 502/m,
    'proxy_ssl_protocols TLSv1.2 rejects a TLSv1.3-only origin with NTLS off');

$r = http_get('/tls-list-allowed', PeerAddr => '127.0.0.1:9118');
like($r, qr/^proto=TLSv1\.3$/m,
    'proxy_ssl_protocols TLSv1.3 reaches a TLSv1.3-only origin with NTLS off');

$r = http_get('/ntls-switch', PeerAddr => '127.0.0.1:9118');
like($r, qr/^HTTP\/1\.. 502/m,
    'proxy_enable_ntls off cannot talk NTLS to an NTLS-only origin');

###############################################################################
