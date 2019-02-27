#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with proxy to ssl backend.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl http_v2 proxy/)
	->has_daemon('openssl')->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / { }
        location /proxy_ssl/ {
            proxy_pass https://127.0.0.1:8081/;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
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
$t->run();

###############################################################################

# request body with an empty DATA frame proxied to ssl backend
# "zero size buf in output" alerts seen

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/proxy_ssl/', body_more => 1 });
$s->h2_body('');
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'empty request body');

###############################################################################
