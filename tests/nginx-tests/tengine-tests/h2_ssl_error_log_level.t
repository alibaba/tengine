#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited
# TCP RST during HTTP/2 processing must not be promoted to an SSL error.

use warnings;
use strict;
use Test::More;
use Socket qw/ SOL_SOCKET SO_LINGER /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl http_v2 proxy socket_ssl_alpn/)
	->has_daemon('openssl')->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');
%%TEST_GLOBALS%%
daemon off;
events { }
http {
    %%TEST_GLOBALS_HTTP%%
    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;
    http2 on;

    server {
        listen 127.0.0.1:8443 ssl;
        error_log %%TESTDIR%%/default.log info;
        location / { return 200 "ok"; }
        location /body { proxy_pass http://127.0.0.1:8081; }
    }
    server {
        listen 127.0.0.1:8444 ssl;
        ssl_handshake_error_log_level error;
        error_log %%TESTDIR%%/raised.log info;
        error_log %%TESTDIR%%/errors.log error;
        location / { return 200 "ok"; }
        location /body { proxy_pass http://127.0.0.1:8081; }
    }
}
EOF

$t->write_file('openssl.conf', <<'EOF');
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();
system('openssl req -x509 -new '
	. "-config $d/openssl.conf -subj /CN=localhost/ "
	. "-out $d/localhost.crt -keyout $d/localhost.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate: $!\n";

$t->run();

for my $port (8443, 8444) {
	my $socket = http('', start => 1, SSL => 1,
		PeerAddr => '127.0.0.1:' . port($port),
		SSL_alpn_protocols => ['h2'])
		or die "Can't establish TLS connection\n";
	my $h2 = Test::Nginx::HTTP2->new(undef, socket => $socket);
	my $sid = $h2->new_stream();
	my $frames = $h2->read(all => [{ sid => $sid, fin => 1 }]);
	my ($headers) = grep { $_->{type} eq 'HEADERS' } @$frames;
	is($headers->{headers}->{':status'}, 200, "HTTP/2 request - $port");

	# Drain the response, then keep another stream active awaiting its body.

	$h2->new_stream({ method => 'POST', path => '/body', body_more => 1 });
	$h2->h2_ping('12345678');
	$h2->read(all => [{ type => 'PING' }]);
	setsockopt($socket, SOL_SOCKET, SO_LINGER, pack('ii', 1, 0))
		or die "Can't enable abortive close: $!\n";
	$socket->close(SSL_no_shutdown => 1);

	my $name = $port == 8443 ? 'default.log' : 'raised.log';
	my $reset = qr/SSL_read\(\) failed.*reset by peer.*processing HTTP\/2/;
	my $log = '';
	for (1 .. 50) {
		$log = read_log($name);
		last if $log =~ $reset;
		select undef, undef, undef, 0.1;
	}
	like($log, qr/\[info\].*$reset/, "HTTP/2 TCP reset - info on $port");
}

unlike(read_log('raised.log'), qr/\[error\].*SSL_read\(\) failed/,
	'handshake promotion does not affect HTTP/2 reads');
unlike(read_log('errors.log'), qr/SSL_read\(\) failed/,
	'error-only log excludes client HTTP/2 TCP resets');

sub read_log {
	my ($name) = @_;
	open my $fh, '<', "$d/$name" or return '';
	local $/;
	return <$fh>;
}
