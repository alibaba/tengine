#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# $ssl_client_enc_cert / $ssl_client_raw_enc_cert: expose the client
# encryption certificate of a TLCP mutual handshake, which otherwise
# stays unreachable ("ssl_client_cert" only returns the sign peer).
# Both variables must stay empty for a plain TLS mutual handshake, so
# the server also carries an RSA certificate and accepts TLS clients.

# Note: the variables compile to empty stubs when Tengine is built
# against Tongsuo 8.4.x; the file is skipped below when nginx rejects
# the gate directive at start-up on Tongsuo older than 8.5.0.

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

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/tongsuo/bin/openssl";

my $t = Test::Nginx->new()->has(qw/http http_ssl/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:9130 ssl;
        server_name  localhost;

        enable_ntls      on;
        # also gates try_run(): this directive needs Tongsuo 8.5.0, the
        # same version the enc-certificate variables need, so on older
        # libraries nginx fails to start here and the file is skipped.
        ssl_ntls_cert_key_usage_check on;
        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:RSA;
        ssl_verify_client           on;
        ssl_client_certificate      client_ca_chain_rsa.crt;

        location / {
            return 200 "sign=[$ssl_client_s_dn] enc=[$ssl_client_enc_cert]";
        }

        location /raw {
            return 200 "raw=[$ssl_client_raw_enc_cert]";
        }

        location /tls {
            return 200 "c=[$ssl_client_cert] e=[$ssl_client_enc_cert] r=[$ssl_client_raw_enc_cert]";
        }
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "server");
make_sm2_ca_subca_end_certs($t, "client");
make_rsa_end_cert($t);

# the RSA client certificate must verify too, so the trust list used
# for ssl_verify_client carries the SM2 chain plus the RSA certificate
$t->write_file('client_ca_chain_rsa.crt',
    $t->read_file('client_ca_chain.crt') . $t->read_file('rsa.crt'));

# Gate on the nginx binary: ssl_ntls_cert_key_usage_check in the config
# above is rejected at start-up on Tongsuo older than 8.5.0, so try_run()
# skips the file there.  The enc-certificate variables need the same
# version, so this keeps the gate off the openssl CLI version.
$t->try_run('Tongsuo 8.5.0 required for the enc certificate variables')
    ->plan(10);

###############################################################################

my $d = $t->testdir();

my $cmd = "$openssl s_client -connect localhost:9130 -quiet -ign_eof"
    . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
    . " -CAfile $d/client_ca_chain.crt"
    . " -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key"
    . " -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key";

# feed the request with printf: /bin/echo -e is not portable to macOS
my $body = `printf "GET / HTTP/1.0\\r\\n\\r\\n" | $cmd 2>&1`;

like($body, qr/sign=\[CN=client_sign\]/, 'sign subject exposed as before');
like($body, qr/enc=\[-----BEGIN CERTIFICATE/, 'enc certificate exposed in PEM');

# the exposed PEM is exactly the client encryption certificate
my $pem = $t->read_file('client_enc.crt');
$pem =~ s/-----[^-]+-----//g;
$pem =~ s/\s+//g;
my $flat = $body;
$flat =~ s/\s+//g;
like($flat, qr/\Q$pem\E/, 'exposed enc certificate is the enc one');

# $ssl_client_raw_enc_cert returns the very same certificate verbatim
my $pem_raw = $t->read_file('client_enc.crt');
my $raw_body = `printf "GET /raw HTTP/1.0\\r\\n\\r\\n" | $cmd 2>&1`;

like($raw_body, qr/raw=\[\Q$pem_raw\E\]/s,
    'raw enc certificate is the exact client enc PEM');

my $sign_b64 = $t->read_file('client_sign.crt');
$sign_b64 =~ s/-----[^-]+-----//g;
$sign_b64 =~ s/\s+//g;
my $raw_flat = $raw_body;
$raw_flat =~ s/-----[^-]+-----//g;
$raw_flat =~ s/\s+//g;

unlike($raw_flat, qr/\Q$sign_b64\E/,
    'raw enc certificate is not the sign certificate');

# plain TLS mutual handshake with an RSA certificate: the enc variables
# stay empty while $ssl_client_cert is set, so the emptiness is NTLS
# semantics and not a broken test harness
my $tls_cmd = "$openssl s_client -connect localhost:9130 -quiet -ign_eof"
    . " -tls1_2 -cipher aRSA"
    . " -CAfile $d/rsa.crt"
    . " -cert $d/rsa.crt -key $d/rsa.key";
my $tls_body = `printf "GET /tls HTTP/1.0\\r\\n\\r\\n" | $tls_cmd 2>&1`;

like($tls_body, qr/c=\[-----BEGIN CERTIFICATE/,
    'client cert exposed for a plain TLS mutual handshake');

like($tls_body, qr/e=\[\]/,
    'enc cert variable empty for a plain TLS handshake');

like($tls_body, qr/r=\[\]/,
    'raw enc cert variable empty for a plain TLS handshake');

# Session resumption: Tongsuo serializes only the sign peer certificate
# into the session, not the encryption chain, so on a resumed session the
# enc variables are empty even though $ssl_client_cert is set.  Pin this
# down so the documented limitation cannot silently change.
my $sess = "$d/session.pem";
my $full = "$openssl s_client -connect localhost:9130 -quiet -ign_eof"
    . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
    . " -CAfile $d/client_ca_chain.crt"
    . " -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key"
    . " -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key"
    . " -sess_out $sess";
`printf "GET /tls HTTP/1.0\\r\\n\\r\\n" | $full 2>&1`;

my $resume = "$openssl s_client -connect localhost:9130 -quiet -ign_eof"
    . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
    . " -CAfile $d/client_ca_chain.crt"
    . " -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key"
    . " -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key"
    . " -sess_in $sess";
my $reused = `printf "GET /tls HTTP/1.0\\r\\n\\r\\n" | $resume 2>&1`;

like($reused, qr/c=\[-----BEGIN CERTIFICATE/,
    'resumed session still exposes the sign client certificate');
like($reused, qr/e=\[\]/,
    'enc cert variable empty on a resumed session (peer_chain not serialized)');

$t->stop();
