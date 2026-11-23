#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# stream: ssl_ntls_cert_key_usage_check mirrors the http-side directive
# and exposes SSL_CTX_set_ntls_cert_key_usage_check().  Tongsuo 8.5.0
# enables the GB/T 20518 sign/enc keyUsage check by default, so a server
# trusting legacy client certificates issued without keyUsage extensions
# rejects every TLCP mutual handshake after the library upgrade.  With
# the directive switched off the same handshake succeeds, which also
# proves that the rejection really comes from the keyUsage check.
# Unconfigured servers keep the library default.

# Note: the directive is rejected at configuration time when Tengine is
# built against Tongsuo 8.4.x, and the "default rejects" assertions
# assume the 8.5.0 default-on keyUsage check; the file is skipped below
# when the Tongsuo binary reports a version older than 8.5.0.

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

my $openssl_version = `$openssl version 2>/dev/null`;
plan(skip_all => "Tongsuo 8.5.0 or later required, got: $openssl_version")
    unless $openssl_version =~ /(?:Tongsuo|BabaSSL)\s+([0-9]+)\.([0-9]+)/
        && ($1 > 8 || ($1 == 8 && $2 >= 5));

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
    ->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

stream {
    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    # library default (Tongsuo 8.5.0: check on) rejects the legacy
    # client certificates in the TLCP Certificate message
    server {
        listen       127.0.0.1:9165 ssl;
        return       proto=$ssl_protocol;

        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # explicit off permits the legacy client certificates
    server {
        listen       127.0.0.1:9166 ssl;
        return       proto=$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # explicit on behaves like the default
    server {
        listen       127.0.0.1:9167 ssl;
        return       proto=$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }
}

EOF

my $d = $t->testdir();

# proper server dual certificates (with keyUsage)
make_sm2_ca_subca_end_certs($t, "server");

# legacy self-signed SM2 client pair without any keyUsage extension
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

# sanity: the client sign certificate really carries no keyUsage
my $ext = `$openssl x509 -in $d/legacy_sign.crt -noout -ext keyUsage 2>&1`;
unlike($ext, qr/Key Usage/i, 'legacy sign certificate has no keyUsage');

$t->run();

###############################################################################

sub mtls {
    my ($port) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
        . " -CAfile $d/server_ca_chain.crt"
        . " -sign_cert $d/legacy_sign.crt -sign_key $d/legacy_sign.key"
        . " -enc_cert $d/legacy_enc.crt -enc_key $d/legacy_enc.key";
    return `$cmd < /dev/null 2>&1`;
}

unlike(mtls(9165), qr/^proto=NTLS/m,
    'default rejects legacy client certificates without keyUsage');

like(mtls(9166), qr/^proto=NTLS/m,
    'ssl_ntls_cert_key_usage_check off permits legacy client certificates');

unlike(mtls(9167), qr/^proto=NTLS/m,
    'ssl_ntls_cert_key_usage_check on keeps the check enforced');

$t->stop();
