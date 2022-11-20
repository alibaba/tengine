#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream ssl module, ssl_verify_client.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
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

SKIP: {
skip 'Net::SSLeay version >= 1.36 required', 1 if $Net::SSLeay::VERSION < 1.36;

my $ca = join ' ', get(8082, '3.example.com');
is($ca, '/CN=2.example.com', 'no trusted sent');

}

$t->stop();

is($t->read_file('status.log'), "500\n200\n", 'log');

###############################################################################

sub get {
	my ($port, $cert) = @_;

	my $dest_ip = inet_aton('127.0.0.1');
	my $dest_serv_params = sockaddr_in(port($port), $dest_ip);

	socket(my $s, &AF_INET, &SOCK_STREAM, 0) or die "socket: $!";
	connect($s, $dest_serv_params) or die "connect: $!";

	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	Net::SSLeay::set_cert_and_key($ctx, "$d/$cert.crt", "$d/$cert.key")
		or die if $cert;
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");

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
