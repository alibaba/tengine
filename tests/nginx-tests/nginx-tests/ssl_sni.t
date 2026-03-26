#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for Server Name Indication (SNI) TLS extension

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
	->has_daemon('openssl')->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            return 200 $server_name:$ssl_server_name;
        }

        location /protocol {
            return 200 $ssl_protocol;
        }

        location /name {
            return 200 $ssl_session_reused:$ssl_server_name;
        }
    }

    server {
        listen       127.0.0.1:8443;
        server_name  example.com;

        ssl_certificate_key example.com.key;
        ssl_certificate example.com.crt;

        location / {
            return 200 $server_name:$ssl_server_name;
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

foreach my $name ('localhost', 'example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

like(get_cert_cn(), qr!/CN=localhost!, 'default cert');
like(get_cert_cn('example.com'), qr!/CN=example.com!, 'sni cert');

like(get_host('example.com'), qr!example.com:example.com!,
	'host exists, sni exists, and host is equal sni');

like(get_host('example.com', 'example.org'), qr!example.com:example.org!,
	'host exists, sni not found');

TODO: {
local $TODO = 'sni restrictions';

like(get_host('example.com', 'localhost'), qr!400 Bad Request!,
	'host exists, sni exists, and host is not equal sni');

like(get_host('example.org', 'example.com'), qr!400 Bad Request!,
	'host not found, sni exists');

}

# $ssl_server_name in sessions

my $ctx = new IO::Socket::SSL::SSL_Context(
	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
	SSL_session_cache_size => 100);

like(get('/name', 'localhost', $ctx), qr/^\.:localhost$/m, 'ssl server name');

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

like(get('/name', 'localhost', $ctx), qr/^r:localhost$/m,
	'ssl server name - reused');

}

###############################################################################

sub test_tls13 {
	get('/protocol', 'localhost') =~ /TLSv1.3/;
}

sub get_cert_cn {
	my ($host) = @_;
	my $s = http('', start => 1, SSL => 1, SSL_hostname => $host);
	return $s->dump_peer_certificate();
}

sub get_host {
	my ($host, $sni) = @_;
	return http(
		"GET / HTTP/1.0\nHost: $host\n\n",
		SSL => 1,
		SSL_hostname => $sni || $host
	);
}

sub get {
	my ($uri, $host, $ctx) = @_;
	return http_get(
		$uri,
		SSL => 1,
		SSL_hostname => $host,
		SSL_reuse_ctx => $ctx
	);
}

###############################################################################
