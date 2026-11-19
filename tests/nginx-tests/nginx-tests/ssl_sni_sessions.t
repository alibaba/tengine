#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for SSL session resumption with SNI.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl sni rewrite socket_ssl_sni/)
	->has_daemon('openssl')
	->write_file_expand('nginx.conf', <<'EOF');

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
        server_name  default;

        ssl_session_tickets off;
        ssl_session_cache shared:cache1:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused:$ssl_protocol;
        }
    }

    server {
        listen       127.0.0.1:8443;
        server_name  nocache;

        ssl_session_tickets off;
        ssl_session_cache shared:cache2:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  default;

        ssl_session_ticket_key ticket1.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8444;
        server_name  tickets;

        ssl_session_ticket_key ticket2.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
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

$t->write_file('ticket1.key', '1' x 48);
$t->write_file('ticket2.key', '2' x 48);

$t->run();

plan(skip_all => 'no TLSv1.3 sessions, old Net::SSLeay')
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
plan(skip_all => 'no TLSv1.3 sessions, old IO::Socket::SSL')
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
plan(skip_all => 'no TLSv1.3 sessions in LibreSSL')
	if $t->has_module('LibreSSL') && test_tls13();
plan(skip_all => 'no TLS 1.3 session cache in BoringSSL')
	if $t->has_module('BoringSSL|AWS-LC') && test_tls13();

$t->plan(6);

###############################################################################

# check that everything works fine with default server

my $ctx = get_ssl_context();

like(get('default', 8443, $ctx), qr!default:\.!, 'default server');
like(get('default', 8443, $ctx), qr!default:r!, 'default server reused');

# check that sessions are still properly saved and restored
# when using an SNI-based virtual server with different session cache;
# as session resumption happens before SNI, only default server
# settings are expected to matter

# this didn't work before nginx 1.9.6 (and caused segfaults if no session
# cache was configured the SNI-based virtual server), because OpenSSL, when
# creating new sessions, uses callbacks from the default server context, but
# provides access to the SNI-selected server context only (ticket #235)

$ctx = get_ssl_context();

like(get('nocache', 8443, $ctx), qr!nocache:\.!, 'without cache');
like(get('nocache', 8443, $ctx), qr!nocache:r!, 'without cache reused');

# make sure tickets can be used if an SNI-based virtual server
# uses a different set of session ticket keys explicitly set

$ctx = get_ssl_context();

like(get('tickets', 8444, $ctx), qr!tickets:\.!, 'tickets');
like(get('tickets', 8444, $ctx), qr!tickets:r!, 'tickets reused');

###############################################################################

sub get_ssl_context {
	return IO::Socket::SSL::SSL_Context->new(
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_session_cache_size => 100
	);
}

sub get {
	my ($host, $port, $ctx) = @_;
	return http(
		"GET / HTTP/1.0\nHost: $host\n\n",
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host,
		SSL_reuse_ctx => $ctx
	);
}

sub test_tls13 {
	return get('default', 8443) =~ /TLSv1.3/;
}

###############################################################################
