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
#
# The SNI cases pin down that the switch follows the server selected by
# SNI: SSL_set_SSL_CTX() does not carry the field over to the
# connection, so ngx_stream_ssl_servername() copies it explicitly.  Both
# directions are tested (default on + vhost off, default off + vhost on)
# on a single listen port.
#
# The last cases pair the directive with
# "ssl_conf_command enable_ntls_cert_key_usage_check", which sets the same
# switch on the SSL_CTX and is applied after the directive: the command
# takes precedence, and its value must be the one the SNI callback copies
# to the connection.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return stream_sni/);

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
        listen       127.0.0.1:9190 ssl;
        return       proto=$ssl_protocol;

        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # explicit off permits the legacy client certificates
    server {
        listen       127.0.0.1:9191 ssl;
        return       proto=$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # explicit on behaves like the default
    server {
        listen       127.0.0.1:9192 ssl;
        return       proto=$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # SNI port: default on, vhost off.local off.  The per-connection
    # sync in ngx_stream_ssl_servername() must let off.local win.
    server {
        listen       127.0.0.1:9193 ssl;
        server_name  localhost;
        return       proto=default:$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    server {
        listen       127.0.0.1:9193 ssl;
        server_name  off.local;
        return       proto=off:$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # SNI port with the opposite direction: default off, vhost on.local on.
    server {
        listen       127.0.0.1:9194 ssl;
        server_name  localhost;
        return       proto=default-off:$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    server {
        listen       127.0.0.1:9194 ssl;
        server_name  on.local;
        return       proto=on:$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    # "ssl_conf_command enable_ntls_cert_key_usage_check" sets the same
    # switch on the SSL_CTX.  It is applied after the directive and takes
    # precedence over it, and the per-connection copy in the SNI callback
    # must not undo what it set.
    server {
        listen       127.0.0.1:9195 ssl;
        server_name  localhost;
        return       proto=conf-off:$ssl_protocol;

        ssl_conf_command enable_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    server {
        listen       127.0.0.1:9195 ssl;
        server_name  on-cc.local;
        return       proto=on-conf-off:$ssl_protocol;

        ssl_ntls_cert_key_usage_check on;
        ssl_conf_command enable_ntls_cert_key_usage_check off;
        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    server {
        listen       127.0.0.1:9196 ssl;
        server_name  localhost;
        return       proto=conf-on-default:$ssl_protocol;

        ssl_verify_client          on;
        ssl_client_certificate     legacy_sign_enc.crt;
    }

    server {
        listen       127.0.0.1:9196 ssl;
        server_name  off-cc.local;
        return       proto=off-conf-on:$ssl_protocol;

        ssl_ntls_cert_key_usage_check off;
        ssl_conf_command enable_ntls_cert_key_usage_check on;
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

# On Tongsuo older than 8.5.0 the directive is rejected at start-up, so
# nginx fails to start and the whole file is skipped.
$t->try_run('no ssl_ntls_cert_key_usage_check')->plan(13);

# sanity: the client sign certificate really carries no keyUsage
my $ext = `$openssl x509 -in $d/legacy_sign.crt -noout -ext keyUsage 2>&1`;
unlike($ext, qr/Key Usage/i, 'legacy sign certificate has no keyUsage');

###############################################################################

sub mtls {
    my ($port, $sni) = @_;
    $sni = defined $sni ? " -servername $sni" : "";
    my $cmd = "$openssl s_client -connect localhost:$port -quiet -ign_eof"
        . " -enable_ntls -ntls -cipher ECC-SM2-SM4-CBC-SM3"
        . " -CAfile $d/server_ca_chain.crt" . $sni
        . " -sign_cert $d/legacy_sign.crt -sign_key $d/legacy_sign.key"
        . " -enc_cert $d/legacy_enc.crt -enc_key $d/legacy_enc.key";
    return `$cmd < /dev/null 2>&1`;
}

unlike(mtls(9190), qr/^proto=NTLS/m,
    'default rejects legacy client certificates without keyUsage');

like($t->read_file('error.log'), qr/wrong certificate type/,
    'rejection is caused by the keyUsage check');

like(mtls(9191), qr/^proto=NTLS/m,
    'ssl_ntls_cert_key_usage_check off permits legacy client certificates');

unlike(mtls(9192), qr/^proto=NTLS/m,
    'ssl_ntls_cert_key_usage_check on keeps the check enforced');

# SNI: default on, vhost off -> off.local must be permitted
like(mtls(9193, 'off.local'), qr/^proto=off:NTLS/m,
    'SNI vhost off overrides default on');
unlike(mtls(9193), qr/^proto=default:NTLS/m,
    'SNI default on still rejects when no SNI matches');

# SNI: default off, vhost on -> on.local must be rejected
unlike(mtls(9194, 'on.local'), qr/^proto=on:NTLS/m,
    'SNI vhost on overrides default off (check enforced)');
like(mtls(9194), qr/^proto=default-off:NTLS/m,
    'SNI default off still permits when no SNI matches');

# the SNI rejections are also caused by the keyUsage check
like($t->read_file('error.log'), qr/wrong certificate type/,
    'SNI rejections are caused by the keyUsage check');

# ssl_conf_command is applied after the directive and wins over it, and
# its value must be the one copied to the connection by the SNI callback
like(mtls(9195, 'localhost'), qr/^proto=conf-off:NTLS/m,
    'ssl_conf_command off survives the SNI sync on the default server');
like(mtls(9195, 'on-cc.local'), qr/^proto=on-conf-off:NTLS/m,
    'ssl_conf_command off takes precedence over the directive on');
unlike(mtls(9196, 'off-cc.local'), qr/^proto=off-conf-on:NTLS/m,
    'ssl_conf_command on takes precedence over the directive off');

$t->stop();
