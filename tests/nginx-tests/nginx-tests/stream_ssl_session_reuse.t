#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for stream ssl module, session reuse.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl socket_ssl_sslversion socket_ssl_reused/)
	->has_daemon('openssl')->plan(7);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;

    server {
        listen      127.0.0.1:8443 ssl;
        proxy_pass  127.0.0.1:8081;
    }

    server {
        listen      127.0.0.1:8444 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;
    }

    server {
        listen      127.0.0.1:8445 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets off;
    }

    server {
        listen      127.0.0.1:8446 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache builtin;
        ssl_session_tickets off;
    }

    server {
        listen      127.0.0.1:8447 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache builtin:1000;
        ssl_session_tickets off;
    }

    server {
        listen      127.0.0.1:8448 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache none;
        ssl_session_tickets off;
    }

    server {
        listen      127.0.0.1:8449 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache off;
        ssl_session_tickets off;
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

$t->run_daemon(\&http_daemon);

$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# session reuse:
#
# - only tickets, the default
# - tickets and shared cache, should work always
# - only shared cache
# - only builtin cache
# - only builtin cache with explicitly configured size
# - only cache none
# - only cache off

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

is(test_reuse(8443), 1, 'tickets reused');
is(test_reuse(8444), 1, 'tickets and cache reused');

TODO: {
local $TODO = 'no TLSv1.3 session cache in BoringSSL'
	if $t->has_module('BoringSSL|AWS-LC') && test_tls13();

is(test_reuse(8445), 1, 'cache shared reused');
is(test_reuse(8446), 1, 'cache builtin reused');
is(test_reuse(8447), 1, 'cache builtin size reused');

}
}

is(test_reuse(8448), 0, 'cache none not reused');
is(test_reuse(8449), 0, 'cache off not reused');

###############################################################################

sub test_tls13 {
	my $s = stream(
		PeerAddr => '127.0.0.1:' . port(8443),
		SSL => 1
	);
	return ($s->socket()->get_sslversion_int() > 0x303);
}

sub test_reuse {
	my ($port) = @_;

	my $s = stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_session_cache_size => 100
	);
	$s->io("GET / HTTP/1.0$CRLF$CRLF");

	$s = stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_reuse_ctx => $s->socket()
	);

	return $s->socket()->get_session_reused();
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if (/^\x0d?\x0a?$/);
		}

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

EOF

		close $client;
	}
}

###############################################################################
