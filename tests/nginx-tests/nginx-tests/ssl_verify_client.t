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
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
};
plan(skip_all => 'Net::SSLeay not installed') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni/)
	->has_daemon('openssl')->plan(13);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-Verify x$ssl_client_verify:${ssl_client_cert}x;

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
        listen       127.0.0.1:8081 ssl;
        server_name  on;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client on;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  optional;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client optional;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  off;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client off;
        ssl_client_certificate 2.example.com.crt;
        ssl_trusted_certificate 3.example.com.crt;
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  optional.no.ca;

        ssl_certificate_key 1.example.com.key;
        ssl_certificate 1.example.com.crt;

        ssl_verify_client optional_no_ca;
        ssl_client_certificate 2.example.com.crt;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  no.context;

        ssl_verify_client on;
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

SKIP: {
skip 'Net::SSLeay version >= 1.36 required', 1 if $Net::SSLeay::VERSION < 1.36;

my $ca = join ' ', get('optional', '3.example.com');
is($ca, '/CN=2.example.com', 'no trusted sent');

}

like(get('optional', undef, 'localhost'), qr/421 Misdirected/, 'misdirected');

###############################################################################

sub get {
	my ($sni, $cert, $host) = @_;

	local $SIG{PIPE} = 'IGNORE';

	$host = $sni if !defined $host;

	my $s = IO::Socket::INET->new('127.0.0.1:' . port(8081));
	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	Net::SSLeay::set_cert_and_key($ctx, "$d/$cert.crt", "$d/$cert.key")
		or die if $cert;
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_tlsext_host_name($ssl, $sni) == 1 or die;
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");

	Net::SSLeay::write($ssl, 'GET /t HTTP/1.0' . CRLF);
	Net::SSLeay::write($ssl, "Host: $host" . CRLF . CRLF);
	my $buf = Net::SSLeay::read($ssl);
	log_in($buf);
	return $buf unless wantarray();

	my $list = Net::SSLeay::get_client_CA_list($ssl);
	my @names;
	for my $i (0 .. Net::SSLeay::sk_X509_NAME_num($list) - 1) {
		my $name = Net::SSLeay::sk_X509_NAME_value($list, $i);
		push @names, Net::SSLeay::X509_NAME_oneline($name);
	}
	return @names;
}

###############################################################################
