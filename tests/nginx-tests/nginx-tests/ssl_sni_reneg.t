#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module with SNI and renegotiation.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ :DEFAULT CRLF /;

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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->has_daemon('openssl')
	->plan(4);

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

        location / { }
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
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

my ($s, $ssl) = get_ssl_socket();
ok($s, 'connection');

SKIP: {
skip 'connection failed', 3 unless $s;

Net::SSLeay::write($ssl, 'GET / HTTP/1.0' . CRLF);

ok(Net::SSLeay::renegotiate($ssl), 'renegotiation');
ok(Net::SSLeay::set_tlsext_host_name($ssl, 'localhost'), 'SNI');

SKIP: {
skip 'leaves coredump', 1 unless $t->has_version('1.9.8')
	or $ENV{TEST_NGINX_UNSAFE};

Net::SSLeay::write($ssl, 'Host: localhost' . CRLF . CRLF);

is(Net::SSLeay::read($ssl), undef, 'response');

}

}

###############################################################################

sub get_ssl_socket {
	my $s;

	my $dest_ip = inet_aton('127.0.0.1');
	my $dest_serv_params = sockaddr_in(8443, $dest_ip);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		socket($s, &AF_INET, &SOCK_STREAM, 0) or die "socket: $!";
		connect($s, $dest_serv_params) or die "connect: $!";
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_fd( $ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");

	return ($s, $ssl);
}

###############################################################################
