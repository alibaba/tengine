#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for SSL/TLS protocol selection with SNI.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl openssl:1.1.1 socket_ssl_sni/);

eval { defined &Net::SSLeay::CTX_set_ciphersuites or die; };
plan(skip_all => 'Net::SSLeay too old') if $@;

$t->has_daemon('openssl')->plan(4)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;

    server {
        listen       127.0.0.1:8443 ssl default_server;
        listen       127.0.0.1:8444 ssl;
        server_name  one;

        ssl_protocols TLSv1.2;

        add_header X-SSL $ssl_protocol;
    }

    server {
        listen       127.0.0.1:8443;
        listen       127.0.0.1:8444 default_server;
        server_name  two;

        ssl_protocols TLSv1.3;

        add_header X-SSL $ssl_protocol;
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
$t->run();

###############################################################################

like(get('one', 8443), qr!TLSv1.2!, 'default server - TLSv1.2');
like(get('two', 8444), qr!TLSv1.3!, 'default server - TLSv1.3');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.2');

like(get('two', 8443), qr!TLSv1.3!, 'protocol change - TLSv1.3');
like(get('one', 8444), qr!TLSv1.2!, 'protocol change - TLSv1.2');

}

###############################################################################

sub get {
	my ($host, $port) = @_;
	return http(
		"GET / HTTP/1.0\nHost: $host\n\n",
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host
	);
}

###############################################################################
