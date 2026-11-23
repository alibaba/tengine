#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# ssl_force_ntls: an NTLS-only listener enters the NTLS state machine
# directly, rejects plain TLS records, and skips the first-byte preread.
# Force mode is a listen-level property (the record version is checked
# before the ClientHello is parsed), so it is honored on the default
# server and rejected on name-based servers sharing the port.
#
# The forced servers and the dual-stack control server on :9112 offer
# the same certificate material (RSA for TLS, SM2 sign/enc for NTLS)
# and the same cipher list, so ssl_force_ntls is their only difference:
# the "rejects plain TLS" assertions below can be caused by force alone,
# since without force the TLS probes share AES ciphersuites with the
# listener and would complete the handshake and get a response.
#
# The matrix below covers: a forced listener accepting NTLS and
# rejecting TLS; two forced vhosts on one forced port, each serving
# its own sign/enc pair selected by SNI (checked via $ssl_server_name
# and the sign-certificate CN); a dual-stack (non-forced) listener for
# comparison; and the two configuration errors (force without
# enable_ntls, force on a name-based server).

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use lib ".";
use CA qw/ make_sm2_ca_subca_end_certs make_sm2_end_certs
    make_rsa_end_cert /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $openssl = $ENV{'TEST_OPENSSL_BINARY'} || "/opt/tongsuo/bin/openssl";

my $openssl_version = `$openssl version 2>/dev/null`;
plan(skip_all => "Tongsuo 8.4.0 or later required, got: $openssl_version")
    unless $openssl_version =~ /(?:Tongsuo|BabaSSL)\s+([0-9]+)\.([0-9]+)/
        && ($1 > 8 || ($1 == 8 && $2 >= 4));

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->plan(13);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    # 1) single forced listener: NTLS only
    server {
        listen       127.0.0.1:9110 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_force_ntls   on;
        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "one proto=$ssl_protocol";
        }
    }

    # 2) two forced vhosts sharing a forced port, distinct dual-cert pairs
    server {
        listen       127.0.0.1:9111 ssl;
        server_name  a.local;

        enable_ntls      on;
        ssl_force_ntls   on;
        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "A $ssl_server_name $ssl_protocol";
        }
    }

    # b.local serves its own self-signed dual pair, distinct from a.local
    server {
        listen       127.0.0.1:9111;
        server_name  b.local;

        enable_ntls      on;
        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;
        ssl_sign_certificate        b_sign.crt;
        ssl_sign_certificate_key    b_sign.key;
        ssl_enc_certificate         b_enc.crt;
        ssl_enc_certificate_key     b_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "B $ssl_server_name $ssl_protocol";
        }
    }

    # 3) dual-stack listener (no force) for comparison
    server {
        listen       127.0.0.1:9112 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_certificate_key rsa.key;
        ssl_certificate     rsa.crt;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "D proto=$ssl_protocol";
        }
    }
}

EOF

make_rsa_end_cert($t);
make_sm2_ca_subca_end_certs($t, "server");
make_sm2_end_certs($t, "b");

$t->run();

###############################################################################

my $d = $t->testdir();

sub cli {
    my (%a) = @_;
    my $cmd = "$openssl s_client -connect localhost:$a{port} -quiet -ign_eof";
    $cmd .= " -servername $a{sni}" if defined $a{sni};
    if ($a{ntls}) {
        $cmd .= " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
            . " -CAfile $d/server_ca_chain.crt";
    } elsif ($a{tls}) {
        $cmd .= " $a{tls} -cipher HIGH:!aNULL";
    }
    # A Host header is sent only when asked for.  Without a server name
    # nginx routes the request to the default server of the port, as
    # without SNI, so the vhost cases below name their vhost in the request.
    my $req = 'GET / HTTP/1.0\r\n';
    $req .= "Host: $a{host}\r\n" if defined $a{host};
    $req .= '\r\n';
    # printf is used instead of "echo -e": BSD echo (macOS) does not
    # interpret backslash escapes and would send a literal "-e ..." line.
    return `printf '$req' | $cmd 2>&1`;
}

# 1) single forced listener
like(cli(port => 9110, ntls => 1), qr/^one proto=NTLS/m,
    'forced listener accepts NTLS');
unlike(cli(port => 9110, tls => '-tls1_2'), qr/^one proto=/m,
    'forced listener rejects plain TLS');

# 2) two forced vhosts by SNI on a forced port.  Each probe sends a Host
# header matching its SNI name: the handshake certificate is chosen by SNI,
# but the vhost that answers is chosen by the Host header.
like(cli(port => 9111, sni => 'a.local', host => 'a.local', ntls => 1),
    qr/^A a\.local NTLS/m, 'forced vhost A selected by SNI over NTLS');
like(cli(port => 9111, sni => 'a.local', host => 'a.local', ntls => 1),
    qr/CN ?= ?server_sign$/m, 'forced vhost A presents its own sign certificate');
like(cli(port => 9111, sni => 'b.local', host => 'b.local', ntls => 1),
    qr/^B b\.local NTLS/m, 'forced vhost B selected by SNI over NTLS');
like(cli(port => 9111, sni => 'b.local', host => 'b.local', ntls => 1),
    qr/CN ?= ?b_sign$/m, 'forced vhost B presents its own sign certificate');
unlike(cli(port => 9111, sni => 'b.local', tls => '-tls1_2'),
    qr/^B b\.local/m, 'forced port rejects plain TLS even by SNI');

# 3) dual-stack listener for comparison
like(cli(port => 9112, ntls => 1), qr/^D proto=NTLS/m,
    'dual-stack listener accepts NTLS');
like(cli(port => 9112, tls => '-tls1_2'), qr/^D proto=TLS/m,
    'dual-stack listener accepts TLS');

# 4) configuration errors, checked with "tengine -t" and a dedicated log
# so the expected emergency stays out of the error.log the framework
# checks on teardown.
my $bin = $Test::Nginx::NGINX;
my $d2 = $t->testdir();

sub bad_conf {
    my ($name, $server) = @_;

    my $file = "$d2/$name.conf";
    open my $fh, '>', $file or die "can't open $file: $!";
    print $fh <<EOF;
worker_processes  1;
daemon off;

events {
}

http {
$server
}
EOF
    close $fh;

    return `$bin -t -p $d2/ -c $name.conf -e $name.error.log 2>&1`;
}

my $no_enable = bad_conf('force_no_enable', <<'EOF');
    server {
        listen       127.0.0.1:9113 ssl;
        server_name  localhost;

        ssl_force_ntls   on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }
EOF

my $sni_force = bad_conf('force_sni', <<'EOF');
    server {
        listen       127.0.0.1:9114 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }

    server {
        listen       127.0.0.1:9114;
        server_name  sni.local;

        enable_ntls      on;
        ssl_force_ntls   on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
    }
EOF

unlike($no_enable, qr/syntax is ok/,
    'force without enable_ntls rejected at config test');
like($no_enable, qr/ssl_force_ntls.*requires.*enable_ntls/s,
    'error message points at the enable_ntls requirement');

unlike($sni_force, qr/syntax is ok/,
    'force on a name-based server rejected at config test');
like($sni_force, qr/ssl_force_ntls.*only allowed.*default server/s,
    'error message points at the default-server requirement');

$t->stop();
