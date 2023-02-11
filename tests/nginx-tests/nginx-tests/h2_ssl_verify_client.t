#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with ssl, ssl_verify_client.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL->can_client_sni() or die; };
plan(skip_all => 'IO::Socket::SSL with OpenSSL SNI support required') if $@;
eval { IO::Socket::SSL->can_alpn() or die; };
plan(skip_all => 'OpenSSL ALPN support required') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni http_v2/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    ssl_verify_client optional_no_ca;

    add_header X-Verify $ssl_client_verify;

    server {
        listen       127.0.0.1:8080 ssl http2;
        server_name  localhost;

        ssl_client_certificate client.crt;

        location / { }
    }

    server {
        listen       127.0.0.1:8080 ssl http2;
        server_name  example.com;

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

foreach my $name ('localhost', 'client') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('t', 'SEE-THIS');

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

my $s = get_ssl_socket();
plan(skip_all => 'no alpn') unless $s->alpn_selected();
$t->plan(3);

###############################################################################

is(get('localhost')->{'x-verify'}, 'SUCCESS', 'success');
like(get('example.com')->{'x-verify'}, qr/FAILED/, 'failed');
is(get('localhost', 'example.com')->{':status'}, '421', 'misdirected');

###############################################################################

sub get_ssl_socket {
	my ($sni) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => port(8080),
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_alpn_protocols => [ 'h2' ],
			SSL_hostname => $sni,
			SSL_cert_file => "$d/client.crt",
			SSL_key_file => "$d/client.key",
			SSL_error_trap => sub { die $_[1] }
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub get {
	my ($sni, $host) = @_;

	$host = $sni if !defined $host;

	my $s = get_ssl_socket($sni);
	my $sess = Test::Nginx::HTTP2->new(port(8080), socket => $s);
	my $sid = $sess->new_stream({ headers => [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/t', mode => 1 },
		{ name => ':authority', value => $host, mode => 1 }]});
	my $frames = $sess->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{'headers'};
}

###############################################################################
