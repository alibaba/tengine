#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Regression: a fresh SSL_CTX does not necessarily carry the library
# defaults of the NTLS switches.  Tongsuo applies the OpenSSL
# system_default configuration (OPENSSL_CONF) when creating the CTX,
# which can set enable_ntls_cert_key_usage_check=off and
# enable_force_ntls=on.  The merged directive values must therefore
# reach the SSL_CTX themselves:
#
# - the keyUsage value is written unconditionally, including the "on"
#   that an unconfigured server resolves to; skipping the setter for
#   "on" let the external policy win on connections for which the SNI
#   callback selects no other virtual server (no SNI, or no matching
#   server_name), silently accepting legacy certificates that an
#   explicit "ssl_ntls_cert_key_usage_check on" must reject;
# - the force switch is reset on the CTX when the directive is off
#   (the default); otherwise the external policy forced NTLS on every
#   connection past the directive, rejecting plain TLS on a dual-stack
#   port.  "on" needs no CTX write: the per-connection
#   SSL_enable_force_ntls() call already enforces it, and
#   ssl_conf_command keeps its precedence over both.
#
# Both http and stream are covered, for "on", for "off", and for an
# unconfigured server, which resolves to the same default.
#
# nginx is started with OPENSSL_CONF pointing at a system_default policy
# that turns the keyUsage check off and force on.  The keyUsage witness
# proves that the policy is really in effect inside the nginx process:
# nginx proxies to a server presenting legacy certificates, and that
# upstream handshake only succeeds because the policy turned the
# client-side check off (the upstream SSL_CTX is not touched by the
# directive).

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

my $t = Test::Nginx->new()
    ->has(qw/http http_ssl proxy stream stream_ssl stream_return/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    # explicit on must reject the legacy client certificates even though
    # the external system_default policy turns the check off; no SNI is
    # sent, so the value must come from the SSL_CTX itself
    server {
        listen       127.0.0.1:9197 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_ntls_cert_key_usage_check on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3;
        ssl_verify_client           on;
        ssl_client_certificate      legacy_sign_enc.crt;

        location / {
            return 200 "body on $ssl_protocol";
        }
    }

    # an unconfigured server resolves to "on" and must reject as well
    server {
        listen       127.0.0.1:9203 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3;
        ssl_verify_client           on;
        ssl_client_certificate      legacy_sign_enc.crt;

        location / {
            return 200 "body default $ssl_protocol";
        }
    }

    # explicit off keeps permitting the legacy client certificates
    server {
        listen       127.0.0.1:9199 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_ntls_cert_key_usage_check off;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3;
        ssl_verify_client           on;
        ssl_client_certificate      legacy_sign_enc.crt;

        location / {
            return 200 "body off $ssl_protocol";
        }
    }

    # witness origin: presents the legacy self-signed pair (no keyUsage)
    # as its own certificates and requests no client certificate
    server {
        listen       127.0.0.1:9200 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_sign_certificate        legacy_sign.crt;
        ssl_sign_certificate_key    legacy_sign.key;
        ssl_enc_certificate         legacy_enc.crt;
        ssl_enc_certificate_key     legacy_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3;

        location / {
            return 200 "body witness $ssl_protocol";
        }
    }

    server {
        listen       127.0.0.1:9201;

        # nginx as a TLCP client: the upstream SSL_CTX is not touched by
        # the directive, so the handshake to the legacy origin only
        # succeeds while the system_default policy turns the client-side
        # check off inside this nginx process
        location / {
            proxy_enable_ntls           on;
            proxy_ssl_session_reuse     off;
            proxy_ssl_trusted_certificate     legacy_sign_enc.crt;
            proxy_ssl_ciphers           ECC-SM2-SM4-CBC-SM3;

            proxy_pass https://127.0.0.1:9200;
        }
    }

    # dual-stack ports for the force switch: the external policy sets
    # enable_force_ntls=on, the directive default (off) must still
    # accept plain TLS
    server {
        listen       127.0.0.1:9205 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_certificate             rsa.crt;
        ssl_certificate_key         rsa.key;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "body dual $ssl_protocol";
        }
    }

    # explicit off behaves like the default
    server {
        listen       127.0.0.1:9206 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_force_ntls   off;
        ssl_certificate             rsa.crt;
        ssl_certificate_key         rsa.key;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "body dual $ssl_protocol";
        }
    }

    # explicit on rejects plain TLS and serves NTLS only
    server {
        listen       127.0.0.1:9207 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_force_ntls   on;
        ssl_certificate             rsa.crt;
        ssl_certificate_key         rsa.key;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "body dual $ssl_protocol";
        }
    }

    # ssl_conf_command is applied after the directive and keeps its
    # precedence: force on via the command overrides the directive off
    server {
        listen       127.0.0.1:9208 ssl;
        server_name  localhost;

        enable_ntls      on;
        ssl_force_ntls   off;
        ssl_conf_command enable_force_ntls on;
        ssl_certificate             rsa.crt;
        ssl_certificate_key         rsa.key;
        ssl_sign_certificate        server_sign.crt;
        ssl_sign_certificate_key    server_sign.key;
        ssl_enc_certificate         server_enc.crt;
        ssl_enc_certificate_key     server_enc.key;
        ssl_ciphers    ECC-SM2-SM4-CBC-SM3:ECC-SM2-SM4-GCM-SM3:HIGH:!aNULL;

        location / {
            return 200 "body dual $ssl_protocol";
        }
    }
}

stream {
    enable_ntls  on;
    ssl_sign_certificate        server_sign.crt;
    ssl_sign_certificate_key    server_sign.key;
    ssl_enc_certificate         server_enc.crt;
    ssl_enc_certificate_key     server_enc.key;

    # same regression on the stream side: no SNI is sent
    server {
        listen       127.0.0.1:9198 ssl;
        return       proto=on:$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # an unconfigured server resolves to "on" and must reject as well
    server {
        listen       127.0.0.1:9204 ssl;
        return       proto=default:$ssl_protocol;

        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # explicit off keeps permitting the legacy client certificates
    server {
        listen       127.0.0.1:9202 ssl;
        return       proto=off:$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }
}

EOF

my $d = $t->testdir();

# proper server dual certificates (with keyUsage) and an RSA certificate
# for the dual-stack ports
make_sm2_ca_subca_end_certs($t, "server");
make_rsa_end_cert($t);

# legacy self-signed SM2 pair without any keyUsage extension, used both
# as the client certificates and as the witness origin certificates
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

# the external policy Tongsuo applies at SSL_CTX creation time
$t->write_file('openssl.cnf', <<'EOF');
nginx=init
openssl_conf=init
[init]
ssl_conf=ssl
[ssl]
system_default=policy
[policy]
enable_ntls_cert_key_usage_check=off
enable_force_ntls=on
EOF

# On Tongsuo older than 8.5.0 the directive is rejected at start-up, so
# nginx fails to start and the whole file is skipped.  OPENSSL_CONF must
# be set while nginx starts (the CTXs are created during configuration
# parsing); the CLI probes below run without it.
{
    local $ENV{OPENSSL_CONF} = "$d/openssl.cnf";
    $t->try_run('no ssl_ntls_cert_key_usage_check')->plan(15);
}

# sanity: the legacy sign certificate really carries no keyUsage
my $ext = `$openssl x509 -in $d/legacy_sign.crt -noout -ext keyUsage 2>&1`;
unlike($ext, qr/Key Usage/i, 'legacy sign certificate has no keyUsage');

###############################################################################

# TLCP mutual handshake with the legacy client pair and no SNI at all
sub probe {
    my ($port, $payload) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -noservername"
        . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
        . " -CAfile $d/server_ca_chain.crt"
        . " -sign_cert $d/legacy_sign.crt -sign_key $d/legacy_sign.key"
        . " -enc_cert $d/legacy_enc.crt -enc_key $d/legacy_enc.key";
    return `printf "$payload" | $cmd 2>&1`;
}

# plain TLS handshake, no SNI; the RSA certificate is self-signed, so
# chain verification may fail, but the response still proves the
# handshake completed
sub tls {
    my ($port, $payload) = @_;
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -noservername -tls1_2 -cipher HIGH:!aNULL";
    return `printf "$payload" | $cmd 2>&1`;
}

my $req  = "GET / HTTP/1.0\\r\\n\\r\\n";
my $ping = "ping\\r\\n";

unlike(probe(9197, $req), qr/^body on NTLS/m,
    'http explicit on rejects legacy client without SNI under policy off');

unlike(probe(9203, $req), qr/^body default NTLS/m,
    'http unconfigured server resolves to on and rejects as well');

unlike(probe(9198, $ping), qr/^proto=on:NTLS/m,
    'stream explicit on rejects legacy client without SNI under policy off');

unlike(probe(9204, $ping), qr/^proto=default:NTLS/m,
    'stream unconfigured server resolves to on and rejects as well');

like($t->read_file('error.log'), qr/wrong certificate type/,
    'rejections are caused by the keyUsage check');

like(probe(9199, $req), qr/^body off NTLS/m,
    'http explicit off still permits legacy client certificates');

like(probe(9202, $ping), qr/^proto=off:NTLS/m,
    'stream explicit off still permits legacy client certificates');

# witness: the proxied handshake to the legacy origin succeeds only
# because the system_default policy turned the client-side check off
# inside the nginx process
my $witness = http_get('/', PeerAddr => '127.0.0.1:9201');
like($witness, qr/body witness NTLS/,
    'the system_default policy is in effect inside nginx');

like(tls(9205, $req), qr/^body dual TLSv1/m,
    'force unset accepts plain TLS under the force-on policy');

like(tls(9206, $req), qr/^body dual TLSv1/m,
    'force off accepts plain TLS under the force-on policy');

unlike(tls(9207, $req), qr/^body dual/m,
    'force on rejects plain TLS');

like(probe(9207, $req), qr/^body dual NTLS/m,
    'force on still serves NTLS');

unlike(tls(9208, $req), qr/^body dual/m,
    'ssl_conf_command enable_force_ntls on overrides the directive off');

like(probe(9208, $req), qr/^body dual NTLS/m,
    'the conf_command force-on server serves NTLS');

$t->stop();