#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module with SNI and renegotiation.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl_sni/)
	->has_daemon('openssl')->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        location / { }
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost2;

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

$t->run();

###############################################################################

my ($s, $ssl);

$s = http('', start => 1, SSL => 1);
ok($s, 'connection');

SKIP: {
skip 'connection failed', 3 unless $s;

local $SIG{PIPE} = 'IGNORE';

$s->print('GET / HTTP/1.0' . CRLF);

# Note: this uses IO::Socket::SSL::_get_ssl_object() internal method.
# While not exactly correct, it looks like there is no other way to
# trigger renegotiation with IO::Socket::SSL, and this seems to be
# good enough for tests.

$ssl = $s->_get_ssl_object();
ok(Net::SSLeay::renegotiate($ssl), 'renegotiation');
ok(Net::SSLeay::set_tlsext_host_name($ssl, 'localhost'), 'SNI');

$s->print('Host: localhost' . CRLF . CRLF);

ok(!http_end($s), 'response');

}

# virtual servers

$s = http('', start => 1, PeerAddr => '127.0.0.1:' . port(8444), SSL => 1);
ok($s, 'connection 2');

SKIP: {
skip 'connection failed', 3 unless $s;

local $SIG{PIPE} = 'IGNORE';

$s->print('GET / HTTP/1.0' . CRLF);

# Note: this uses IO::Socket::SSL::_get_ssl_object() internal method.
# While not exactly correct, it looks like there is no other way to
# trigger renegotiation with IO::Socket::SSL, and this seems to be
# good enough for tests.

$ssl = $s->_get_ssl_object();
ok(Net::SSLeay::renegotiate($ssl), 'renegotiation');
ok(Net::SSLeay::set_tlsext_host_name($ssl, 'localhost'), 'SNI');

$s->print('Host: localhost' . CRLF . CRLF);

ok(!http_end($s), 'virtual servers');

}

###############################################################################
