#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with ssl.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ SOL_SOCKET SO_RCVBUF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl http_v2/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        lingering_close off;

        location / { }
    }
}

EOF

eval { require IO::Socket::SSL; die if $IO::Socket::SSL::VERSION < 1.56; };
plan(skip_all => 'IO::Socket::SSL version >= 1.56 required') if $@;

eval { IO::Socket::SSL->can_alpn() or die; };
plan(skip_all => 'IO::Socket::SSL with OpenSSL ALPN support required') if $@;

eval { exists &Net::SSLeay::P_alpn_selected or die; };
plan(skip_all => 'Net::SSLeay with OpenSSL ALPN support required') if $@;

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
$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 500000)));

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

plan(skip_all => 'no ALPN negotiation') unless defined getconn();
$t->plan(3);

###############################################################################

SKIP: {
$t->{_configure_args} =~ /LibreSSL ([\d\.]+)/;
skip 'LibreSSL too old', 1 if defined $1 and $1 lt '3.4.0';
$t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;
skip 'OpenSSL too old', 1 if defined $1 and $1 lt '1.1.0';

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.4');

ok(!get_ssl_socket(['unknown']), 'alpn rejected');

}

}

like(http_get('/', socket => get_ssl_socket(['http/1.1'])),
	qr/200 OK/, 'alpn to HTTP/1.1 fallback');

my $s = getconn(['http/1.1', 'h2']);
my $sid = $s->new_stream();
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'alpn to HTTP/2');

# client cancels last stream after HEADERS has been created,
# while some unsent data was left in the SSL buffer
# HEADERS frame may stuck in SSL buffer and won't be sent producing alert

$s = getconn(['http/1.1', 'h2']);
$s->{socket}->setsockopt(SOL_SOCKET, SO_RCVBUF, 1024*1024) or die $!;
$sid = $s->new_stream({ path => '/tbig.html' });

select undef, undef, undef, 0.2;
$s->h2_rst($sid, 8);

$sid = $s->new_stream({ path => '/tbig.html' });

select undef, undef, undef, 0.2;
$s->h2_rst($sid, 8);

$t->stop();

###############################################################################

sub getconn {
	my ($alpn) = @_;
	$alpn = ['h2'] if !defined $alpn;

	my $sock = get_ssl_socket($alpn);
	my $s = Test::Nginx::HTTP2->new(undef, socket => $sock)
		if $sock->alpn_selected();
}

sub get_ssl_socket {
	my ($alpn) = @_;
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
			SSL_alpn_protocols => $alpn,
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

###############################################################################
