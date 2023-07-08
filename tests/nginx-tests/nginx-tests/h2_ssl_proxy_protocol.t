#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with proxy_protocol.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl http_v2 realip socket_ssl_alpn/)
	->has_daemon('openssl')->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 proxy_protocol http2 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location /pp {
            set_real_ip_from 127.0.0.1/32;
            real_ip_header proxy_protocol;
            alias %%TESTDIR%%/t.html;
            add_header X-PP $remote_addr;
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
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('t.html', 'SEE-THIS');

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

###############################################################################

my $proxy = 'PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
my $sock = http($proxy, start => 1);
http('', start => 1, socket => $sock, SSL => 1, SSL_alpn_protocols => ['h2']);

SKIP: {
skip 'no ALPN negotiation', 2 unless $sock->alpn_selected();

my $s = Test::Nginx::HTTP2->new(undef, socket => $sock);
my $sid = $s->new_stream({ path => '/pp' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($frame, 'PROXY HEADERS frame');
is($frame->{headers}->{'x-pp'}, '192.0.2.1', 'PROXY remote addr');

}

$sock->close();

# invalid PROXY protocol string

$proxy = 'BOGUS TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
ok(!http($proxy), 'PROXY invalid protocol');

###############################################################################
