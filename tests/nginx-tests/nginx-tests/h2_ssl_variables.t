#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with ssl.

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

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL::SSL_VERIFY_NONE(); };
plan(skip_all => 'IO::Socket::SSL too old') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl http_v2 rewrite/)
	->has_daemon('openssl')->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location /h2 {
            return 200 $http2;
        }
        location /sp {
            return 200 $server_protocol;
        }
        location /scheme {
            return 200 $scheme;
        }
        location /https {
            return 200 $https;
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

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

###############################################################################

my ($s, $sid, $frames, $frame);

my $has_npn = eval { Test::Nginx::HTTP2::new_socket(port(8080), SSL => 1,
	npn => 'h2')->next_proto_negotiated() };
my $has_alpn = eval { Test::Nginx::HTTP2::new_socket(port(8080), SSL => 1,
	alpn => 'h2')->alpn_selected() };

# SSL/TLS connection, NPN

SKIP: {
skip 'OpenSSL NPN support required', 1 unless $has_npn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, npn => 'h2');
$sid = $s->new_stream({ path => '/h2' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'h2', 'http variable - npn');

}

# SSL/TLS connection, ALPN

SKIP: {
skip 'OpenSSL ALPN support required', 1 unless $has_alpn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, alpn => 'h2');
$sid = $s->new_stream({ path => '/h2' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'h2', 'http variable - alpn');

}

# $server_protocol - SSL/TLS connection, NPN

SKIP: {
skip 'OpenSSL NPN support required', 1 unless $has_npn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, npn => 'h2');
$sid = $s->new_stream({ path => '/sp' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'HTTP/2.0', 'server_protocol variable - npn');

}

# $server_protocol - SSL/TLS connection, ALPN

SKIP: {
skip 'OpenSSL ALPN support required', 1 unless $has_alpn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, alpn => 'h2');
$sid = $s->new_stream({ path => '/sp' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'HTTP/2.0', 'server_protocol variable - alpn');

}

# $scheme - SSL/TLS connection, NPN

SKIP: {
skip 'OpenSSL NPN support required', 1 unless $has_npn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, npn => 'h2');
$sid = $s->new_stream({ path => '/scheme' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'https', 'scheme variable - npn');

}

# $scheme - SSL/TLS connection, ALPN

SKIP: {
skip 'OpenSSL ALPN support required', 1 unless $has_alpn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, alpn => 'h2');
$sid = $s->new_stream({ path => '/scheme' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'https', 'scheme variable - alpn');

}

# $https - SSL/TLS connection, NPN

SKIP: {
skip 'OpenSSL NPN support required', 1 unless $has_npn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, npn => 'h2');
$sid = $s->new_stream({ path => '/https' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'on', 'https variable - npn');

}

# $https - SSL/TLS connection, ALPN

SKIP: {
skip 'OpenSSL ALPN support required', 1 unless $has_alpn;

$s = Test::Nginx::HTTP2->new(port(8080), SSL => 1, alpn => 'h2');
$sid = $s->new_stream({ path => '/https' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'on', 'https variable - alpn');

}

###############################################################################
