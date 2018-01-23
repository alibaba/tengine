#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, loading "engine:..." keys.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

plan(skip_all => 'may not work, leaves coredump')
	unless $ENV{TEST_NGINX_UNSAFE};

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->has_daemon('openssl')
	->has_daemon('softhsm')->has_daemon('pkcs11-tool')->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key engine:pkcs11:slot_0-id_00;
        ssl_certificate localhost.crt;

        location / {
            # index index.html by default
        }
        location /proxy {
            proxy_pass https://127.0.0.1:8443/;
        }
    }
}

EOF

# Create a SoftHSM token with a secret key, and configure OpenSSL
# to access it using the pkcs11 engine, see detailed example
# posted by Dmitrii Pichulin here:
#
# http://mailman.nginx.org/pipermail/nginx-devel/2014-October/006151.html
#
# Note that library paths may differ on different systems,
# and may need to be adjusted.

$t->write_file('openssl.conf', <<EOF);
openssl_conf = openssl_def

[openssl_def]
engines = engine_section

[engine_section]
pkcs11 = pkcs11_section

[pkcs11_section]
engine_id = pkcs11
dynamic_path = /usr/local/lib/engines/engine_pkcs11.so
MODULE_PATH = /usr/local/lib/softhsm/libsofthsm.so
init = 0
PIN = 1234

[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

$t->write_file('softhsm.conf', <<EOF);
0:$d/slot0.db
EOF

$ENV{SOFTHSM_CONF} = "$d/softhsm.conf";
$ENV{OPENSSL_CONF} = "$d/openssl.conf";

foreach my $name ('localhost') {
	system('softhsm --init-token --slot 0 --label "NginxZero" '
		. '--pin 1234 --so-pin 1234 '
		. ">>$d/openssl.out 2>&1");

	system('pkcs11-tool --module=/usr/local/lib/softhsm/libsofthsm.so '
		. '-p 1234 -l -k -d 0 -a nx_key_0 --key-type rsa:2048 '
		. ">>$d/openssl.out 2>&1");

	system('openssl req -x509 -new -engine pkcs11 '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyform engine -text -key id_00 "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

$t->write_file('index.html', '');

###############################################################################

like(http_get('/proxy'), qr/200 OK/, 'ssl engine keys');

###############################################################################
