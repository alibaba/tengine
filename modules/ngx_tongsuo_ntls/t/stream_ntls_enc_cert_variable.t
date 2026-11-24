#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# stream: $ssl_client_enc_cert / $ssl_client_raw_enc_cert expose the
# client encryption certificate of a TLCP mutual handshake with the
# same semantics as the http side: the former prepends a tab to every
# PEM line except the first (like $ssl_client_cert), the latter returns
# the PEM as-is; both stay empty when no client certificate was sent.

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
use CA qw/ make_sm2_ca_subca_end_certs /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/tongsuo/bin/openssl";

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

stream {
    enable_ntls  on;
    # also gates try_run(): this directive needs Tongsuo 8.5.0, the same
    # version the enc-certificate variables need, so on older libraries
    # nginx fails to start here and the file is skipped.
    ssl_ntls_cert_key_usage_check on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    server {
        listen  127.0.0.1:9138 ssl;
        return  $ssl_client_enc_cert;

        ssl_verify_client on;
        ssl_client_certificate client_ca_chain.crt;
    }

    server {
        listen  127.0.0.1:9139 ssl;
        return  $ssl_client_raw_enc_cert;

        ssl_verify_client on;
        ssl_client_certificate client_ca_chain.crt;
    }

    server {
        listen  127.0.0.1:9143 ssl;
        return  "v=$ssl_client_verify c=[$ssl_client_cert] e=[$ssl_client_enc_cert] r=[$ssl_client_raw_enc_cert]";

        ssl_verify_client optional;
        ssl_client_certificate client_ca_chain.crt;
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "server");
make_sm2_ca_subca_end_certs($t, "client");

# Gate on the nginx binary: ssl_ntls_cert_key_usage_check in the config
# above is rejected at start-up on Tongsuo older than 8.5.0, so try_run()
# skips the file there.  The enc-certificate variables need the same
# version, so this keeps the gate off the openssl CLI version.
$t->try_run('Tongsuo 8.5.0 required for the enc certificate variables')
    ->plan(5);

###############################################################################

my $d = $t->testdir();

sub mtls {
    my ($port) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
        . " -CAfile $d/server_ca_chain.crt"
        . " -sign_cert $d/client_sign.crt -sign_key $d/client_sign.key"
        . " -enc_cert $d/client_enc.crt -enc_key $d/client_enc.key";
    return `$cmd < /dev/null 2>/dev/null`;
}

sub flatten {
    my ($text) = @_;
    $text =~ s/-----[^-]+-----//g;
    $text =~ s/\s+//g;
    return $text;
}

my $enc_out = mtls(9138);
my $raw_out = mtls(9139);
my $enc_pem = $t->read_file('client_enc.crt');

# the exposed PEM is exactly the client encryption certificate
is(flatten($enc_out), flatten($enc_pem),
    '$ssl_client_enc_cert is the client enc certificate');

like($enc_out,
    qr/\A-----BEGIN CERTIFICATE-----\n(\t\S+\n)+\t-----END CERTIFICATE-----\z/,
    '$ssl_client_enc_cert tab-indents every line but the first');

is($raw_out, $enc_pem,
    '$ssl_client_raw_enc_cert is the exact enc certificate PEM');

my $sign_b64 = flatten($t->read_file('client_sign.crt'));

unlike(flatten($raw_out), qr/\Q$sign_b64\E/,
    '$ssl_client_raw_enc_cert is not the sign certificate');

# no client certificate: the enc variables stay empty, and the regular
# $ssl_client_cert is empty as well, so this is not a harness artifact
my $cmd = "$openssl s_client -connect localhost:9143 -quiet -ign_eof"
    . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
    . " -CAfile $d/server_ca_chain.crt";
my $none_out = `$cmd < /dev/null 2>/dev/null`;

is($none_out, 'v=NONE c=[] e=[] r=[]',
    'no client certificate leaves enc cert variables empty');

$t->stop();
