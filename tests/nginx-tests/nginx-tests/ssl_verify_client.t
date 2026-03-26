#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, ssl_verify_client.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni socket_ssl_sni/)
	->has_daemon('openssl')->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-Verify x$ssl_client_verify:${ssl_client_cert}x;
    add_header X-Protocol $ssl_protocol;

    ssl_session_cache shared:SSL:1m;
    ssl_session_tickets off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  on;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  optional;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  off;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client off;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  optional.no.ca;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  no.context;

        ssl_verify_client on;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  dup;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client optional;
        ssl_client_certificate dup.2.example.com.crt;
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

$t->write_file('dup.2.example.com.crt', $t->read_file('2.example.com.crt') x 2);

sleep 1 if $^O eq 'MSWin32';

$t->write_file('t', 'SEE-THIS');

$t->run();

###############################################################################

like(http_get('/t'), qr/x:x/, 'plain connection');
like(get('on'), qr/400 Bad Request/, 'no cert');
like(get('no.context'), qr/400 Bad Request/, 'no server cert');
like(get('optional'), qr/NONE:x/, 'no optional cert');
like(get('optional', '1.example.com'), qr/400 Bad/, 'bad optional cert');
like(get('optional.no.ca', '1.example.com'), qr/FAILED.*BEGIN/,
	'bad optional_no_ca cert');
like(get('off', '2.example.com'), qr/NONE/, 'off cert');
like(get('off', '3.example.com'), qr/NONE/, 'off cert trusted');

like(get('localhost', '2.example.com'), qr/SUCCESS.*BEGIN/, 'good cert');
like(get('optional', '2.example.com'), qr/SUCCESS.*BEGI/, 'good cert optional');
like(get('optional', '3.example.com'), qr/SUCCESS.*BEGIN/, 'good cert trusted');

TODO: {
local $TODO = 'broken TLSv1.3 CA list in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

my $ca = join ' ', get('optional', '3.example.com');
is($ca, '/CN=2.example.com', 'no trusted sent');

$ca = join ' ', get('dup');
is($ca, '/CN=2.example.com', 'no duplicates sent');

}

like(get('optional', undef, 'localhost'), qr/421 Misdirected/, 'misdirected');

###############################################################################

sub test_tls13 {
	get('optional') =~ /TLSv1.3/;
}

sub get {
	my ($sni, $cert, $host) = @_;

	$host = $sni if !defined $host;

	my $s = http(
		"GET /t HTTP/1.0" . CRLF .
		"Host: $host" . CRLF . CRLF,
		start => 1,
		SSL => 1,
		SSL_hostname => $sni,
		$cert ? (
		SSL_cert_file => "$d/$cert.crt",
		SSL_key_file => "$d/$cert.key"
		) : ()
	);

	return http_end($s) unless wantarray();

	# Note: this uses IO::Socket::SSL::_get_ssl_object() internal method.
	# While not exactly correct, it looks like there is no other way to
	# obtain CA list with IO::Socket::SSL, and this seems to be good
	# enough for tests.

	my $ssl = $s->_get_ssl_object();
	my $list = Net::SSLeay::get_client_CA_list($ssl);
	my @names;
	for my $i (0 .. Net::SSLeay::sk_X509_NAME_num($list) - 1) {
		my $name = Net::SSLeay::sk_X509_NAME_value($list, $i);
		push @names, Net::SSLeay::X509_NAME_oneline($name);
	}
	return @names;
}

###############################################################################
