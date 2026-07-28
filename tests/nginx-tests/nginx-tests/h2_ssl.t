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

my $t = Test::Nginx->new()->has(qw/http http_ssl http_v2 socket_ssl_alpn/)
	->has_daemon('openssl');

plan(skip_all => 'no ALPN support in OpenSSL')
	if $t->has_module('OpenSSL') and not $t->has_feature('openssl:1.0.2');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        http2 on;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        lingering_close off;

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
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');
$t->write_file('tbig.html',
	join('', map { sprintf "XX%06dXX", $_ } (1 .. 500000)));

$t->run()->plan(4);

###############################################################################

SKIP: {
skip 'LibreSSL too old', 1
	if $t->has_module('LibreSSL')
	and not $t->has_feature('libressl:3.4.0');
skip 'OpenSSL too old', 1
	if $t->has_module('OpenSSL')
	and not $t->has_feature('openssl:1.1.0');

ok(!get_ssl_socket(['unknown']), 'alpn rejected');

}

like(http_get('/', socket => get_ssl_socket(['http/1.1'])),
	qr/200 OK/, 'alpn to HTTP/1.1 fallback');

my $s = getconn(['http/1.1', 'h2']);
my $sid = $s->new_stream();
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'alpn to HTTP/2');

# h2c preface on ssl-enabled socket is rejected as invalid HTTP/1.x request,
# ensure that HTTP/2 auto-detection doesn't kick in

like(http("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n",
	PeerAddr => '127.0.0.1:' . port(8443)), qr/Bad Request/,
	'no h2c on ssl socket');

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
	my $sock = get_ssl_socket($alpn);
	Test::Nginx::HTTP2->new(undef, socket => $sock);
}

sub get_ssl_socket {
	my ($alpn) = @_;
	return http('', start => 1, SSL => 1, SSL_alpn_protocols => $alpn);
}

###############################################################################
