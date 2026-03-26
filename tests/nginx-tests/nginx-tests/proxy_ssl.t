#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for proxy to ssl backend.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy http_ssl socket_ssl/)
	->has_daemon('openssl')->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8081 ssl;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        ssl_session_cache builtin;

        location / {
            add_header X-Session $ssl_session_reused;
            add_header X-Protocol $ssl_protocol;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /ssl_reuse {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_session_reuse on;
        }

        location /ssl {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_session_reuse off;
        }

        location /timeout {
            proxy_pass https://127.0.0.1:8082;
            proxy_connect_timeout 3s;
        }

        location /timeout_h {
            proxy_pass https://127.0.0.1:8083;
            proxy_connect_timeout 1s;
        }
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

$t->write_file('big.html', 'xxxxxxxxxx' x 72000);
$t->write_file('index.html', '');

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run_daemon(\&http_daemon, port(8082));
$t->run_daemon(\&http_daemon, port(8083));
$t->run();
$t->waitforsocket('127.0.0.1:' . port(8082));
$t->waitforsocket('127.0.0.1:' . port(8083));

###############################################################################

like(http_get('/ssl'), qr/200 OK.*X-Session: \./s, 'ssl');
like(http_get('/ssl'), qr/200 OK.*X-Session: \./s, 'ssl 2');
like(http_get('/ssl_reuse'), qr/200 OK.*X-Session: \./s, 'ssl session new');

TODO: {
local $TODO = 'no TLS 1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && http_get('/ssl') =~ /TLSv1.3/;

like(http_get('/ssl_reuse'), qr/200 OK.*X-Session: r/s, 'ssl session reused');
like(http_get('/ssl_reuse'), qr/200 OK.*X-Session: r/s, 'ssl session reused 2');

}

SKIP: {
skip 'long test', 1 unless $ENV{TEST_NGINX_UNSAFE};

like(http_get('/timeout'), qr/200 OK/, 'proxy connect timeout');

}

like(http_get('/timeout_h'), qr/504 Gateway/, 'proxy handshake timeout');

is(length(Test::Nginx::http_content(http_get('/ssl/big.html'))), 720000,
	'big length');

###############################################################################

sub http_daemon {
	my ($port) = @_;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		if ($port == port(8083)) {
			sleep 3;

			close $client;
			next;
		}

		my $headers = '';
		my $uri = '';

		# would fail on waitforsocket

		eval {
			IO::Socket::SSL->start_SSL($client,
				SSL_server => 1,
				SSL_cert_file => "$d/localhost.crt",
				SSL_key_file => "$d/localhost.key",
				SSL_error_trap => sub { die $_[1] }
			);
		};
		next if $@;

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
		next if $uri eq '';

		if ($uri eq '/timeout') {
			sleep 4;

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

EOF
		}

		close $client;
	}
}

###############################################################################
