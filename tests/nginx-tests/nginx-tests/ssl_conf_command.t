#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, ssl_conf_command.

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

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
};
plan(skip_all => 'Net::SSLeay not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl/)
	->has_daemon('openssl');

$t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;
plan(skip_all => 'OpenSSL too old') unless defined $1 and $1 ge '1.0.2';
plan(skip_all => 'no ssl_conf_command') if $t->has_module('BoringSSL');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_protocols TLSv1.2;

        ssl_session_tickets off;
        ssl_conf_command Options SessionTicket;

        ssl_prefer_server_ciphers on;
        ssl_conf_command Options -ServerPreference;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
        ssl_conf_command Certificate override.crt;
        ssl_conf_command PrivateKey override.key;
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

foreach my $name ('localhost', 'override') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run()->plan(3);

###############################################################################

my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");

my ($s, $ssl) = get_ssl_socket();
like(Net::SSLeay::dump_peer_certificate($ssl), qr/CN=override/, 'Certificate');

my $ses = Net::SSLeay::get_session($ssl);
($s, $ssl) = get_ssl_socket(ses => $ses);
ok(Net::SSLeay::session_reused($ssl), 'SessionTicket');

($s, $ssl) = get_ssl_socket(ciphers =>
	'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384');
is(Net::SSLeay::get_cipher($ssl),
	'ECDHE-RSA-AES128-GCM-SHA256', 'ServerPreference');

###############################################################################

sub get_ssl_socket {
	my (%extra) = @_;

	my $s = IO::Socket::INET->new('127.0.0.1:' . port(8443));
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_session($ssl, $extra{ses}) if $extra{ses};
	Net::SSLeay::set_cipher_list($ssl, $extra{ciphers}) if $extra{ciphers};
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
}

###############################################################################
