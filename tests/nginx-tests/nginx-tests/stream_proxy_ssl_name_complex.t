#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for proxy to ssl backend, use of Server Name Indication
# (proxy_ssl_name, proxy_ssl_server_name directives) with complex value.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return sni/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse off;

    server {
        listen      127.0.0.1:8081;
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8085;

        proxy_ssl_server_name on;
        proxy_ssl_name x${server_port}x;
    }

    server {
        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        listen  127.0.0.1:8085 ssl;
        return  $ssl_server_name;
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

$t->run()->plan(2);

###############################################################################

my ($p1, $p2) = (port(8081), port(8082));

is(stream("127.0.0.1:$p1")->read(), "x${p1}x", 'name 1');
is(stream("127.0.0.1:$p2")->read(), "x${p2}x", 'name 2');

###############################################################################
