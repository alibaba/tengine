#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for http ssl module, session reuse.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl rewrite socket_ssl/)
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

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        location / {
            return 200 "body $ssl_session_reused";
        }
        location /protocol {
            return 200 "body $ssl_protocol";
        }
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8445 ssl;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8446 ssl;
        server_name  localhost;

        ssl_session_cache builtin;
        ssl_session_tickets off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8447 ssl;
        server_name  localhost;

        ssl_session_cache builtin:1000;
        ssl_session_tickets off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8448 ssl;
        server_name  localhost;

        ssl_session_cache none;
        ssl_session_tickets off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8449 ssl;
        server_name  localhost;

        ssl_session_cache off;
        ssl_session_tickets off;

        location / {
            return 200 "body $ssl_session_reused";
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

is(test_reuse(8443), 1, 'tickets reused');
is(test_reuse(8444), 1, 'tickets and cache reused');

TODO: {
local $TODO = 'no TLSv1.3 session cache in BoringSSL'
	if $t->has_module('BoringSSL|AWS-LC') && test_tls13();

is(test_reuse(8445), 1, 'cache shared reused');
is(test_reuse(8446), 1, 'cache builtin reused');
is(test_reuse(8447), 1, 'cache builtin size reused');

}
}

is(test_reuse(8448), 0, 'cache none not reused');
is(test_reuse(8449), 0, 'cache off not reused');

$t->stop();

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crit');

###############################################################################

sub test_tls13 {
	return http_get('/protocol', SSL => 1) =~ /TLSv1.3/;
}

sub test_reuse {
	my ($port) = @_;

	my $s = http_get(
		'/', PeerAddr => '127.0.0.1:' . port($port), start => 1,
		SSL => 1,
		SSL_session_cache_size => 100
	);
	http_end($s);

	my $r = http_get(
		'/', PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_reuse_ctx => $s
	);

	return ($r =~ qr/^body r$/m) ? 1 : 0;
}

###############################################################################
