#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream pass module.

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

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl stream_pass stream_ssl_preread stream_geo/)
	->has(qw/http http_ssl sni socket_ssl_sni/)->has_daemon('openssl')
	->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    log_format test $status;
    access_log %%TESTDIR%%/test.log test;

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:8443 ssl;
        server_name  default;
        pass         127.0.0.1:8092;

        ssl_preread  on;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  sni;
        pass         127.0.0.1:8091;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  sni;
        pass         127.0.0.1:8092;
    }

    geo $var {
        default      127.0.0.1:8092;
    }

    server {
        listen       127.0.0.1:8081;
        pass         $var;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8091 ssl;
        listen       127.0.0.1:8092;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
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

$t->write_file('index.html', '');

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

# passing either to HTTP or HTTPS backend, depending on server_name

TODO: {
todo_skip 'no socket peek', 2 if $^O eq 'MSWin32' or $^O eq 'solaris';

like(http_get('/'), qr/200 OK/, 'pass');
like(http_get('/', SSL => 1, SSL_hostname => 'sni',
	PeerAddr => '127.0.0.1:' . port(8080)), qr/200 OK/, 'pass ssl');

}

like(http_get('/', SSL => 1, SSL_hostname => 'sni'), qr/200 OK/,
	'pass ssl handshaked');

unlike(http_get('/', SSL => 1), qr/200 OK/, 'pass with preread');

like(http_get('/', PeerAddr => '127.0.0.1:' . port(8081)), qr/200 OK/,
	'pass variable');

$t->stop();

is($t->read_file('test.log'), "500\n", 'pass with preread - log');

###############################################################################
