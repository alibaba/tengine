#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, ssl_reject_handshake.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl sni socket_ssl/)
	->has_daemon('openssl')->plan(7);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-Name $ssl_server_name;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_reject_handshake on;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  virtual;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
    }

    server {
        listen       127.0.0.1:8082;
        server_name  virtual1;
    }

    server {
        listen       127.0.0.1:8082;
        server_name  virtual2;

        ssl_reject_handshake on;
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

# default virtual server rejected

like(get('default', 8080), qr/unrecognized name/, 'default rejected');
like(get(undef, 8080), qr/unrecognized name/, 'absent sni rejected');
like(get('virtual', 8080), qr/virtual/, 'virtual accepted');

# non-default server "virtual2" rejected

like(get('default', 8082), qr/default/, 'default accepted');
like(get(undef, 8082), qr/200 OK(?!.*X-Name)/is, 'absent sni accepted');
like(get('virtual1', 8082), qr/virtual1/, 'virtual 1 accepted');
like(get('virtual2', 8082), qr/unrecognized name/, 'virtual 2 rejected');

###############################################################################

sub get {
	my ($host, $port) = @_;
	my $r = http(
		"GET / HTTP/1.0\nHost: " . ($host || 'localhost') . "\n\n",
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host
	)
		or return "$@";
	return $r;
}

###############################################################################
