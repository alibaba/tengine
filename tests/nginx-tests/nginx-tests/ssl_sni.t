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

my $t = Test::Nginx->new()->has(qw/http http_ssl sni rewrite/)
	->has_daemon('openssl')
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
            return 200 $server_name;
        }
    }

    server {
        listen       127.0.0.1:8443;
        server_name  example.com;

        ssl_certificate_key example.com.key;
        ssl_certificate example.com.crt;

        location / {
            return 200 $server_name;
        }
    }
}

EOF

eval { require IO::Socket::SSL; die if $IO::Socket::SSL::VERSION < 1.56; };
plan(skip_all => 'IO::Socket::SSL version >= 1.56 required') if $@;

eval {
	if (IO::Socket::SSL->can('can_client_sni')) {
		IO::Socket::SSL->can_client_sni() or die;
	}
};
plan(skip_all => 'IO::Socket::SSL with OpenSSL SNI support required') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

$t->plan(6);

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
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

like(get_cert_cn(), qr!/CN=localhost!, 'default cert');
like(get_cert_cn('example.com'), qr!/CN=example.com!, 'sni cert');

like(https_get_host('example.com'), qr!example.com!,
	'host exists, sni exists, and host is equal sni');

like(https_get_host('example.com', 'example.org'), qr!example.com!,
	'host exists, sni not found');

TODO: {
local $TODO = 'sni restrictions';

like(https_get_host('example.com', 'localhost'), qr!400 Bad Request!,
	'host exists, sni exists, and host is not equal sni');

like(https_get_host('example.org', 'example.com'), qr!400 Bad Request!,
	'host not found, sni exists');

}

###############################################################################

sub get_ssl_socket {
	my ($host) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:8443',
			SSL_hostname => $host,
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_error_trap => sub { die $_[1] }
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub get_cert_cn {
	my ($host) = @_;
	my $s = get_ssl_socket($host);

	return $s->dump_peer_certificate();
}

sub https_get_host {
	my ($host, $sni) = @_;
	my $s = get_ssl_socket($sni ? $sni : $host);

	return http(<<EOF, socket => $s);
GET / HTTP/1.0
Host: $host

EOF
}

###############################################################################
