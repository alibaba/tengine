#!/usr/bin/perl

# (C) Vadim Zhestikov
# (C) Nginx, Inc.

# Tests for http ssl module, $ssl_sigalgs variable.

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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl openssl:1.0.2 socket_ssl/)
	->has_daemon('openssl');

plan(skip_all => 'no TLSv1.2 in Net::SSLeay')
	if Net::SSLeay::SSLeay() < 0x1000100f;

plan(skip_all => 'no sigalgs in BoringSSL')
	if $t->has_module('BoringSSL|AWS-LC');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        add_header X-SigAlgs $ssl_sigalgs;
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');

$t->try_run('no ssl_sigalgs')->plan(1);

###############################################################################

# signature algorithms from the ClientHello, colon-separated:
# TLS scheme names with OpenSSL 4.0+, 0xHHHH codes with older
# versions; rsa_pkcs1_sha256 (0x0401) is advertised by default

like(http_get('/', SSL => 1), qr/rsa_pkcs1_sha256|0x0401/, 'ssl sigalgs');

###############################################################################
