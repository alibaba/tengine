#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream ssl module, ssl_verify_client.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return socket_ssl/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    log_format  status  $status;

    ssl_certificate_key 1.example.com.key;
    ssl_certificate 1.example.com.crt;

    server {
        listen  127.0.0.1:8080;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen  127.0.0.1:8081 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;

        access_log %%TESTDIR%%/status.log status;
    }

    server {
        listen  127.0.0.1:8082 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen  127.0.0.1:8083 ssl;
        return  $ssl_client_verify:$ssl_client_cert;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen  127.0.0.1:8084 ssl;
        return  $ssl_protocol;
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

foreach my $name ('1.example.com', '2.example.com', '3.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run()->plan(10);

###############################################################################

is(stream('127.0.0.1:' . port(8080))->read(), ':', 'plain connection');

is(get(8081), '', 'no cert');
is(get(8082, '1.example.com'), '', 'bad optional cert');
is(get(8082), 'NONE:', 'no optional cert');
like(get(8083, '1.example.com'), qr/FAILED.*BEGIN/, 'bad optional_no_ca cert');

like(get(8081, '2.example.com'), qr/SUCCESS.*BEGIN/, 'good cert');
like(get(8082, '2.example.com'), qr/SUCCESS.*BEGIN/, 'good cert optional');
like(get(8082, '3.example.com'), qr/SUCCESS.*BEGIN/, 'good cert trusted');

TODO: {
local $TODO = 'broken TLSv1.3 CA list in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

my $ca = join ' ', get(8082, '3.example.com');
is($ca, '/CN=2.example.com', 'no trusted sent');

}

$t->stop();

is($t->read_file('status.log'), "500\n200\n", 'log');

###############################################################################

sub test_tls13 {
	get(8084) =~ /TLSv1.3/;
}

sub get {
	my ($port, $cert) = @_;

	my $s = stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : ()
	);

	return $s->read() unless wantarray();

	# Note: this uses IO::Socket::SSL::_get_ssl_object() internal method.
	# While not exactly correct, it looks like there is no other way to
	# obtain CA list with IO::Socket::SSL, and this seems to be good
	# enough for tests.

	my $ssl = $s->socket()->_get_ssl_object();
	my $list = Net::SSLeay::get_client_CA_list($ssl);
	my @names;
	for my $i (0 .. Net::SSLeay::sk_X509_NAME_num($list) - 1) {
		my $name = Net::SSLeay::sk_X509_NAME_value($list, $i);
		push @names, Net::SSLeay::X509_NAME_oneline($name);
	}
	return @names;
}

###############################################################################
