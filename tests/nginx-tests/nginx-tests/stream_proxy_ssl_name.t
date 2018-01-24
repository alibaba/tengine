#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for proxy to ssl backend, use of Server Name Indication
# (proxy_ssl_name, proxy_ssl_server_name directives).

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl http http_ssl sni/)
	->has_daemon('openssl')->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse off;

    upstream u {
        server 127.0.0.1:8086;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;

        proxy_ssl_server_name off;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  u;

        proxy_ssl_server_name on;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_server_name on;
        proxy_ssl_name example.com;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_server_name on;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_server_name on;
        proxy_ssl_name example.com:123;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8086 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            add_header X-Name $ssl_server_name,;
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

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');

$t->run();

###############################################################################

like(http_get('/', socket => getconn('127.0.0.1:8080')),
	qr/200 OK.*X-Name: ,/s, 'no name');
like(http_get('/', socket => getconn('127.0.0.1:8081')),
	qr/200 OK.*X-Name: u,/s, 'name default');
like(http_get('/', socket => getconn('127.0.0.1:8082')),
	qr/200 OK.*X-Name: example.com,/s, 'name override');
like(http_get('/', socket => getconn('127.0.0.1:8083')),
	qr/200 OK.*X-Name: ,/s, 'no ip');
like(http_get('/', socket => getconn('127.0.0.1:8084')),
	qr/200 OK.*X-Name: example.com,/s, 'no port in name');

###############################################################################

sub getconn {
	my $peer = shift;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => $peer || '127.0.0.1:8080'
	)
		or die "Can't connect to nginx: $!\n";

	return $s;
}

###############################################################################
