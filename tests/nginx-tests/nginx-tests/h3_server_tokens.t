#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with server_tokens directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 rewrite cryptx/)
	->has_daemon('openssl')->plan(12);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        location /200 {
            return 200;
        }

        location /404 {
            return 404;
        }

        location /off {
            server_tokens off;

            location /off/200 {
                return 200;
            }

            location /off/404 {
                return 404;
            }
        }

        location /on {
            server_tokens on;

            location /on/200 {
                return 200;
            }

            location /on/404 {
                return 404;
            }
        }

        location /b {
            server_tokens build;

            location /b/200 {
                return 200;
            }

            location /b/404 {
                return 404;
            }
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

$t->run();

###############################################################################

my $re = qr/nginx\/\d+\.\d+\.\d+/;

like(header_server('/200'), qr/^$re$/, 'http3 tokens default 200');
like(header_server('/404'), qr/^$re$/, 'http3 tokens default 404');
like(body('/404'), qr/$re/, 'http3 tokens default 404 body');

is(header_server('/off/200'), 'nginx', 'http3 tokens off 200');
is(header_server('/off/404'), 'nginx', 'http3 tokens off 404');
like(body('/off/404'), qr/nginx(?!\/)/, 'http3 tokens off 404 body');

like(header_server('/on/200'), qr/^$re$/, 'http3 tokens on 200');
like(header_server('/on/404'), qr/^$re$/, 'http3 tokens on 404');
like(body('/on/404'), $re, 'http3 tokens on 404 body');

$re = qr/$re \(.*\)/ if $t->has_module('--build=');

like(header_server('/b/200'), qr/^$re$/, 'http3 tokens build 200');
like(header_server('/b/404'), qr/^$re$/, 'http3 tokens build 404');
like(body('/b/404'), qr/$re/, 'http3 tokens build 404 body');

###############################################################################

sub header_server {
	my ($path) = shift;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $path });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{'server'};
}

sub body {
	my ($path) = shift;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $path });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{'data'};
}

###############################################################################
