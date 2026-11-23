#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for stream ssl module, ssl_force_ntls.
#
# ssl_force_ntls makes an "enable_ntls on" listener NTLS-only: the NTLS
# record version is required before any ClientHello parsing, so plain TLS
# handshakes are rejected.  The runtime part pins the behaviour on two
# identically configured listeners (SM2 dual certificates plus an RSA
# certificate for the TLS side), whose only difference is the extra
# "ssl_force_ntls on" on the forced port: the forced port accepts NTLS
# and rejects TLS1.2, while the control port accepts both, proving the
# rejection is caused by force mode alone.
#
# The configuration part checks with "tengine -t" (and a dedicated error
# log, so the expected emergencies stay out of the error.log the
# framework checks on teardown) that "ssl_force_ntls" without
# "enable_ntls on" is rejected, that it is only allowed in the default
# server of a shared "listen ... ssl" port, and that a server without
# any certificate reports the NTLS-aware message.

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

my $openssl_version = `$openssl version 2>/dev/null`;
plan(skip_all => "Tongsuo 8.4.0 or later required, got: $openssl_version")
    unless $openssl_version =~ /(?:Tongsuo|BabaSSL)\s+([0-9]+)\.([0-9]+)/
        && ($1 > 8 || ($1 == 8 && $2 >= 4));

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
    ->plan(10);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

# NOTE: Tengine defaults to `worker_processes auto;`.
worker_processes 1;

events {
}

stream {
    server {
        listen       127.0.0.1:9162 ssl;

        enable_ntls      on;
        ssl_force_ntls   on;

        ssl_certificate_key         rsa.key;
        ssl_certificate             rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        return "force proto=$ssl_protocol";
    }

    server {
        listen       127.0.0.1:9163 ssl;

        enable_ntls      on;

        ssl_certificate_key         rsa.key;
        ssl_certificate             rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        return "dual proto=$ssl_protocol";
    }
}

EOF

make_sm2_ca_subca_end_certs($t, "server");
make_rsa_end_cert($t);

$t->run();

###############################################################################

sub ntls_probe {
    my ($port) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3";
    return `$cmd 2>&1`;
}

sub tls_probe {
    my ($port) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -tls1_2 -cipher HIGH:!aNULL";
    return `$cmd 2>&1`;
}

# 1-2) forced listener: NTLS accepted, plain TLS rejected
like(ntls_probe(9162), qr/^force proto=NTLSv(\d|\.)+/m,
    'forced listener accepts NTLS');
unlike(tls_probe(9162), qr/^force proto=/m,
    'forced listener rejects plain TLS');

# 3-4) control listener (identical certificates, no force): both accepted
like(tls_probe(9163), qr/^dual proto=TLSv1\.2/m,
    'control listener accepts plain TLS');
like(ntls_probe(9163), qr/^dual proto=NTLSv(\d|\.)+/m,
    'control listener accepts NTLS');

# 5-7) configuration errors, checked with "tengine -t" and a dedicated
# log so the expected emergency stays out of the error.log the framework
# checks on teardown.  Port 9164 is only referenced by the configuration,
# nothing binds at configuration-test time.
my $bin = $Test::Nginx::NGINX;
my $d2 = $t->testdir();

sub bad_conf {
    my ($name, $servers) = @_;

    my $file = "$d2/$name.conf";
    open my $fh, '>', $file or die "can't open $file: $!";
    print $fh <<EOF;
worker_processes  1;
daemon off;

events {
}

stream {
$servers
}
EOF
    close $fh;

    return `$bin -t -p $d2/ -c $name.conf -e $name.error.log 2>&1`;
}

my $no_enable = bad_conf('force_no_enable', <<'EOF');
    server {
        listen       127.0.0.1:9164 ssl;

        ssl_force_ntls   on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }
EOF

my $sni_force = bad_conf('force_sni', <<'EOF');
    server {
        listen       127.0.0.1:9164 ssl;

        enable_ntls      on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }

    server {
        listen       127.0.0.1:9164;
        server_name  sni.local;

        enable_ntls      on;
        ssl_force_ntls   on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }
EOF

my $no_certs = bad_conf('force_no_certs', <<'EOF');
    server {
        listen       127.0.0.1:9164 ssl;

        enable_ntls  on;
    }
EOF

unlike($no_enable, qr/syntax is ok/,
    'force without enable_ntls rejected at config test');
like($no_enable, qr/"ssl_force_ntls" requires "enable_ntls on"/,
    'error message points at the enable_ntls requirement');

unlike($sni_force, qr/syntax is ok/,
    'force on a name-based server rejected at config test');
like($sni_force, qr/"ssl_force_ntls" is only allowed in the default server/,
    'error message points at the default-server requirement');

unlike($no_certs, qr/syntax is ok/,
    'listen ssl without certificates rejected at config test');
like($no_certs,
    qr/no "ssl_certificate", "ssl_enc_certificate" or "ssl_sign_certificate" is defined/,
    'error message mentions the NTLS certificate directives');

$t->stop();
