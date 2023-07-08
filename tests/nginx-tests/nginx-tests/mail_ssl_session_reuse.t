#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for mail ssl module, session reuse.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()
	->has(qw/mail mail_ssl imap socket_ssl_sslversion socket_ssl_reused/)
	->has_daemon('openssl')->plan(7);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    auth_http  http://127.0.0.1:8080;

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;

    server {
        listen    127.0.0.1:8993 ssl;
        protocol  imap;
    }

    server {
        listen    127.0.0.1:8994 ssl;
        protocol  imap;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;
    }

    server {
        listen    127.0.0.1:8995 ssl;
        protocol  imap;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets off;
    }

    server {
        listen    127.0.0.1:8996 ssl;
        protocol  imap;

        ssl_session_cache builtin;
        ssl_session_tickets off;
    }

    server {
        listen    127.0.0.1:8997 ssl;
        protocol  imap;

        ssl_session_cache builtin:1000;
        ssl_session_tickets off;
    }

    server {
        listen    127.0.0.1:8998 ssl;
        protocol  imap;

        ssl_session_cache none;
        ssl_session_tickets off;
    }

    server {
        listen    127.0.0.1:8999 ssl;
        protocol  imap;

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
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

is(test_reuse(8993), 1, 'tickets reused');
is(test_reuse(8994), 1, 'tickets and cache reused');

TODO: {
local $TODO = 'no TLSv1.3 session cache in BoringSSL'
	if $t->has_module('BoringSSL') && test_tls13();

is(test_reuse(8995), 1, 'cache shared reused');
is(test_reuse(8996), 1, 'cache builtin reused');
is(test_reuse(8997), 1, 'cache builtin size reused');

}
}

is(test_reuse(8998), 0, 'cache none not reused');
is(test_reuse(8999), 0, 'cache off not reused');

###############################################################################

sub test_tls13 {
	my $s = Test::Nginx::IMAP->new(SSL => 1);
	return ($s->socket()->get_sslversion_int() > 0x303);
}

sub test_reuse {
	my ($port) = @_;

	my $s = Test::Nginx::IMAP->new(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_session_cache_size => 100
	);
	$s->read();

	$s = Test::Nginx::IMAP->new(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_reuse_ctx => $s->socket()
	);

	return $s->socket()->get_session_reused();
}

###############################################################################
