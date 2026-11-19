#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module, ssl_reject_handshake.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl stream_return sni socket_ssl_sni/)
	->has_daemon('openssl')->plan(7);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_reject_handshake on;
        return $ssl_server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  virtual;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        return $ssl_server_name;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        return $ssl_server_name;
    }

    server {
        listen       127.0.0.1:8082;
        server_name  virtual1;

        return $ssl_server_name;
    }

    server {
        listen       127.0.0.1:8082;
        server_name  virtual2;

        ssl_reject_handshake on;
        return $ssl_server_name;
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

$t->run();

###############################################################################

# default virtual server rejected

like(get('default', 8080), qr/unrecognized name/, 'default rejected');
like(get(undef, 8080), qr/unrecognized name/, 'absent sni rejected');
like(get('virtual', 8080), qr/virtual/, 'virtual accepted');

# non-default server "virtual2" rejected

like(get('default', 8082), qr/default/, 'default accepted');
is(get(undef, 8082), '', 'absent sni accepted');
like(get('virtual1', 8082), qr/virtual1/, 'virtual 1 accepted');
like(get('virtual2', 8082), qr/unrecognized name/, 'virtual 2 rejected');

###############################################################################

sub get {
	my ($host, $port) = @_;
	my $s = stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host
	);

	log_in("ssl sni: $host") if defined $host;

	return $s->read() || $@;
}

###############################################################################
