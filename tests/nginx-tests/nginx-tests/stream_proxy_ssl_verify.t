#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for proxy to ssl backend, backend certificate verification.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
	->has_daemon('openssl')->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_ssl on;
    proxy_ssl_verify on;

    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_name example.com;
        proxy_ssl_trusted_certificate 1.example.com.crt;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_name foo.example.com;
        proxy_ssl_trusted_certificate 1.example.com.crt;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8086;

        proxy_ssl_name no.match.example.com;
        proxy_ssl_trusted_certificate 1.example.com.crt;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  127.0.0.1:8087;

        proxy_ssl_name 2.example.com;
        proxy_ssl_trusted_certificate 2.example.com.crt;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  127.0.0.1:8087;

        proxy_ssl_name bad.example.com;
        proxy_ssl_trusted_certificate 2.example.com.crt;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  127.0.0.1:8087;

        proxy_ssl_trusted_certificate 1.example.com.crt;
        proxy_ssl_session_reuse off;
    }

    server {
        listen      127.0.0.1:8086 ssl;
        proxy_ssl   off;
        return      OK;

        ssl_certificate 1.example.com.crt;
        ssl_certificate_key 1.example.com.key;
    }

    server {
        listen      127.0.0.1:8087 ssl;
        proxy_ssl   off;
        return      OK;

        ssl_certificate 2.example.com.crt;
        ssl_certificate_key 2.example.com.key;
    }
}

EOF

$t->write_file('openssl.1.example.com.conf', <<EOF);
[ req ]
prompt = no
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[ req_distinguished_name ]
commonName=no.match.example.com

[ v3_req ]
subjectAltName = DNS:example.com,DNS:*.example.com
EOF

$t->write_file('openssl.2.example.com.conf', <<EOF);
[ req ]
prompt = no
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
commonName=2.example.com
EOF

my $d = $t->testdir();

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.$name.conf "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

sleep 1 if $^O eq 'MSWin32';

$t->run();

###############################################################################

# subjectAltName

is(get(8080), 'OK', 'verify');
is(get(8081), 'OK', 'verify wildcard');
isnt(get(8082), 'OK', 'verify fail');

# commonName

is(get(8083), 'OK', 'verify cn');
isnt(get(8084), 'OK', 'verify cn fail');

# untrusted

isnt(get(8085), 'OK', 'untrusted');

###############################################################################

sub get {
	stream('127.0.0.1:' . port(shift))->read();
}

###############################################################################
