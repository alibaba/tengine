#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# proxy_ssl_conf_command enable_ntls_cert_key_usage_check off: the
# documented migration path for proxying to a legacy NTLS upstream whose
# sign/enc certificates lack a keyUsage extension.  Tongsuo 8.5.0 runs
# the keyUsage check on the client side too, so without the relaxation
# the frontend's handshake to the upstream fails; with it the handshake
# succeeds.  This pins down that the README's migration path works.

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

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/tongsuo/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    # NTLS origin presenting legacy (no keyUsage) dual certificates.
    server {
        listen       127.0.0.1:9134 ssl;
        server_name  localhost;

        enable_ntls  on;
        ssl_sign_certificate        legacy_sign.crt;
        ssl_sign_certificate_key    legacy_sign.key;
        ssl_enc_certificate         legacy_enc.crt;
        ssl_enc_certificate_key     legacy_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3;

        location / {
            return 200 "origin proto=$ssl_protocol";
        }
    }

    server {
        listen       127.0.0.1:9135;

        # default: the client-side keyUsage check is enforced, so the
        # handshake to the legacy upstream fails.
        location /strict {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse off;
            proxy_ssl_trusted_certificate     legacy_sign_enc.crt;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9134;
        }

        # the documented relaxation: disable the client-side check.
        location /relaxed {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse off;
            proxy_ssl_conf_command    enable_ntls_cert_key_usage_check off;
            proxy_ssl_trusted_certificate     legacy_sign_enc.crt;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9134;
        }
    }
}

EOF

my $d = $t->testdir();

# legacy self-signed SM2 dual pair without any keyUsage extension,
# presented by the upstream server
$t->write_file('legacy.cnf', <<EOF);
[ req ]
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

foreach my $name ('sign', 'enc') {
    system("$openssl ecparam -genkey -name SM2 -out $d/legacy_$name.key "
        . ">>$d/openssl.out 2>&1") == 0 or die "Can't create key: $!\n";

    system("$openssl req -x509 -new -key $d/legacy_$name.key "
        . "-config $d/legacy.cnf -subj /CN=legacy_$name/ "
        . "-out $d/legacy_$name.crt "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for legacy_$name: $!\n";
}

$t->write_file('legacy_sign_enc.crt',
    $t->read_file('legacy_sign.crt') . $t->read_file('legacy_enc.crt'));

# Gate on the nginx binary via try_run(): the config above uses
# proxy_ssl_conf_command enable_ntls_cert_key_usage_check, which is
# applied through SSL_CONF_cmd() at configuration time; on Tongsuo older
# than 8.5.0 the command is unknown there, the merge fails and nginx
# refuses to start, so the file is skipped.  This keeps the gate off the
# openssl CLI version, like the sibling tests.
$t->try_run('Tongsuo 8.5.0 required for the keyUsage conf command')
    ->plan(3);

###############################################################################

# sanity: the upstream sign certificate really carries no keyUsage
my $ext = `$openssl x509 -in $d/legacy_sign.crt -noout -ext keyUsage 2>&1`;
unlike($ext, qr/Key Usage/i, 'upstream sign certificate has no keyUsage');

# /strict: the legacy upstream certificate fails the client-side keyUsage
# check, so the frontend cannot complete the handshake and returns 502.
my $strict = http_get('/strict', PeerAddr => '127.0.0.1:9135');
like($strict, qr/502 Bad Gateway/,
    'default client-side keyUsage check rejects the legacy upstream');

# /relaxed: with proxy_ssl_conf_command enable_ntls_cert_key_usage_check
# off the handshake succeeds and the origin responds.
my $relaxed = http_get('/relaxed', PeerAddr => '127.0.0.1:9135');
like($relaxed, qr/origin proto=NTLS/,
    'proxy_ssl_conf_command off permits the legacy upstream');

$t->stop();
