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

my $t = Test::Nginx->new()->has(qw/http proxy http_ssl/)->has_daemon('openssl')
	->has_daemon('softhsm2-util');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8081 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key engine:pkcs11:id_00;

        location / {
            # index index.html by default
        }

        location /proxy {
            proxy_pass https://127.0.0.1:8081/;
        }

        location /var {
            proxy_pass https://127.0.0.1:8082/;
            proxy_ssl_name localhost;
            proxy_ssl_server_name on;
        }
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate $ssl_server_name.crt;
        ssl_certificate_key engine:pkcs11:id_00;

        location / {
            # index index.html by default
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
# Note that library paths vary on different systems,
# and may need to be adjusted.

my $libsofthsm2_path;
my @so_paths = (
	'/usr/lib/softhsm',		# Debian-based
	'/usr/local/lib/softhsm',	# FreeBSD
	'/opt/local/lib/softhsm',	# MacPorts
	'/lib64',			# RHEL-based
	split /:/, $ENV{TEST_NGINX_SOFTHSM} || ''
);

for my $so_path (@so_paths) {
	$so_path .= '/libsofthsm2.so';
	if (-e $so_path) {
		$libsofthsm2_path = $so_path;
		last;
	}
};

plan(skip_all => "libsofthsm2.so not found") unless $libsofthsm2_path;

my $openssl_conf = <<EOF;
openssl_conf = openssl_def

[openssl_def]
engines = engine_section

[engine_section]
pkcs11 = pkcs11_section

[pkcs11_section]
engine_id = pkcs11
dynamic_path = /usr/local/lib/engines/pkcs11.so
MODULE_PATH = $libsofthsm2_path
init = 1
PIN = 1234

[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

$openssl_conf =~ s|^(?=dynamic_path)|# |m if $^O ne 'freebsd';
$t->write_file('openssl.conf', $openssl_conf);

my $d = $t->testdir();

$t->write_file('softhsm2.conf', <<EOF);
directories.tokendir = $d/tokens/
objectstore.backend = file
EOF

mkdir($d . '/tokens');

$ENV{SOFTHSM2_CONF} = "$d/softhsm2.conf";
$ENV{OPENSSL_CONF} = "$d/openssl.conf";

foreach my $name ('localhost') {
	system('softhsm2-util --init-token --slot 0 --label NginxZero '
		. '--pin 1234 --so-pin 1234 '
		. ">>$d/openssl.out 2>&1");

	system("openssl genrsa -out $d/$name.key 2048 "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";

	system("softhsm2-util --import $d/$name.key --id 00 --label nx_key_0 "
		. '--token NginxZero --pin 1234 '
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't import private key: $!\n";

	system('openssl req -x509 -new '
		. "-subj /CN=$name/ -out $d/$name.crt -text "
		. "-engine pkcs11 -keyform engine -key id_00 "
		. ">>$d/openssl.out 2>&1") == 0
		or plan(skip_all => "missing engine");
}

$t->run()->plan(2);

$t->write_file('index.html', '');

###############################################################################

like(http_get('/proxy'), qr/200 OK/, 'ssl engine keys');
like(http_get('/var'), qr/200 OK/, 'ssl_certificate with variable');

###############################################################################
