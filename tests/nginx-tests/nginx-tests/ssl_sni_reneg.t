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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)->has_daemon('openssl');

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
        listen       127.0.0.1:8080 ssl;
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        location / { }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost2;

        location / { }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
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

{
	my (undef, $ssl) = get_ssl_socket(8080);
	plan(skip_all => "TLS 1.3 forbids renegotiation")
		if Net::SSLeay::version($ssl) > 0x0303;
}

$t->plan(8);

###############################################################################

my ($ossl) = $t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;

my ($s, $ssl) = get_ssl_socket(8080);
ok($s, 'connection');

SKIP: {
skip 'connection failed', 3 unless $s;

local $SIG{PIPE} = 'IGNORE';

Net::SSLeay::write($ssl, 'GET / HTTP/1.0' . CRLF);

ok(Net::SSLeay::renegotiate($ssl), 'renegotiation');
ok(Net::SSLeay::set_tlsext_host_name($ssl, 'localhost'), 'SNI');

Net::SSLeay::write($ssl, 'Host: localhost' . CRLF . CRLF);

TODO: {
local $TODO = 'not yet' if $ossl ge '1.1.1' and $^O eq 'linux'
	and !$t->has_version('1.15.2');

ok(!Net::SSLeay::read($ssl), 'response');

}

}

# virtual servers
# in [1.15.4..1.15.5) SSL_OP_NO_RENEGOTIATION is cleared in servername callback

($s, $ssl) = get_ssl_socket(8081);
ok($s, 'connection 2');

SKIP: {
skip 'connection failed', 3 unless $s;

local $SIG{PIPE} = 'IGNORE';

Net::SSLeay::write($ssl, 'GET / HTTP/1.0' . CRLF);

ok(Net::SSLeay::renegotiate($ssl), 'renegotiation');
ok(Net::SSLeay::set_tlsext_host_name($ssl, 'localhost'), 'SNI');

Net::SSLeay::write($ssl, 'Host: localhost' . CRLF . CRLF);

TODO: {
local $TODO = 'not yet' if $ossl ge '1.1.1' and $^O eq 'linux'
	and !$t->has_version('1.15.2');

ok(!Net::SSLeay::read($ssl), 'virtual servers');

}

}

###############################################################################

sub get_ssl_socket {
	my ($port) = @_;
	my $s;

	my $dest_ip = inet_aton('127.0.0.1');
	my $dest_serv_params = sockaddr_in(port($port), $dest_ip);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
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
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::set_tlsext_host_name($ssl, 'localhost');
	Net::SSLeay::connect($ssl) or die("ssl connect");

	return ($s, $ssl);
}

###############################################################################
