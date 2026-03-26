#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for TLS session resumption with HTTP/3.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 cryptx/)
	->has_daemon('openssl')->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    add_header X-Session $ssl_session_reused always;

    server {
        listen       127.0.0.1:%%PORT_8943_UDP%% quic;
        server_name  localhost;
    }

    server {
        listen       127.0.0.1:%%PORT_8944_UDP%% quic;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;
    }

    server {
        listen       127.0.0.1:%%PORT_8945_UDP%% quic;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets off;
    }

    server {
        listen       127.0.0.1:%%PORT_8946_UDP%% quic;
        server_name  localhost;

        ssl_session_cache builtin;
        ssl_session_tickets off;
    }

    server {
        listen       127.0.0.1:%%PORT_8947_UDP%% quic;
        server_name  localhost;

        ssl_session_cache builtin:1000;
        ssl_session_tickets off;
    }

    server {
        listen       127.0.0.1:%%PORT_8948_UDP%% quic;
        server_name  localhost;

        ssl_session_cache none;
        ssl_session_tickets off;
    }

    server {
        listen       127.0.0.1:%%PORT_8949_UDP%% quic;
        server_name  localhost;

        ssl_session_cache off;
        ssl_session_tickets off;
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

# session reuse:
#
# - only tickets, the default
# - tickets and shared cache, should work always
# - only shared cache
# - only builtin cache
# - only builtin cache with explicitly configured size
# - only cache none
# - only cache off

TODO: {
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL');

is(test_reuse(8943), 1, 'tickets reused');
is(test_reuse(8944), 1, 'tickets and cache reused');

local $TODO = 'no TLSv1.3 session cache in BoringSSL'
	if $t->has_module('BoringSSL|AWS-LC');

is(test_reuse(8945), 1, 'cache shared reused');
is(test_reuse(8946), 1, 'cache builtin reused');
is(test_reuse(8947), 1, 'cache builtin size reused');

}

is(test_reuse(8948), 0, 'cache none not reused');
is(test_reuse(8949), 0, 'cache off not reused');

$t->stop();

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crit');

###############################################################################

sub test_reuse {
	my ($port) = @_;

	my $s = Test::Nginx::HTTP3->new($port);
	my $frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

	my $psk_list = $s->{psk_list};

	$s = Test::Nginx::HTTP3->new($port, psk_list => $psk_list);
	$frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{'x-session'} eq 'r' ? 1 : 0;
}

###############################################################################
