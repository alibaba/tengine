#!/usr/bin/perl

# (C) Aleksei Bavshin
# (C) Nginx, Inc.

# Tests for http ssl module, loading "store:..." keys.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()
	->has(qw/http http_ssl geo openssl:1.1.1 socket_ssl_sni/)
	->has_daemon('openssl');

plan(skip_all => 'BoringSSL') if $t->has_module('BoringSSL|AWS-LC');
plan(skip_all => 'not yet') unless $t->has_version('1.29.0');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geo $localhost {
        default localhost;
    }

    geo $pass {
        default pass;
    }

    add_header X-SSL $ssl_server_name;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  default;

        ssl_certificate localhost.crt;
        ssl_certificate_key store:file:%%TESTDIR%%/localhost.key;
    }

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  variable;

        ssl_certificate localhost.crt;
        ssl_certificate_key store:file:%%TESTDIR%%/$localhost.key;
    }

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  pass;

        ssl_certificate pass.crt;
        ssl_certificate_key store:file:%%TESTDIR%%/pass.key;

        ssl_password_file password;
    }

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  variable-pass;

        ssl_certificate pass.crt;
        ssl_certificate_key store:file:%%TESTDIR%%/$pass.key;

        ssl_password_file password;
    }

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  variable-no-pass;

        ssl_certificate pass.crt;
        ssl_certificate_key store:file:%%TESTDIR%%/$pass.key;
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

foreach my $name ('pass') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}


$t->write_file('password', 'pass');
$t->write_file('index.html', '');

$t->run()->plan(9);

###############################################################################

like(cert('default'), qr/CN=localhost/, 'default key');
like(get('default'), qr/default/, 'default context');

like(cert('variable'), qr/CN=localhost/, 'key with vars');
like(get('variable'), qr/variable/, 'context with vars');

like(cert('pass'), qr/CN=pass/, 'encrypted key');
like(get('pass'), qr/pass/, 'encrypted context');

like(cert('variable-pass'), qr/CN=pass/, 'encrypted key - vars');
like(get('variable-pass'), qr/variable-pass/, 'encrypted context - vars');

is(cert('variable-no-pass'), undef, 'encrypted key - no pass');

###############################################################################

sub get {
	my $s = get_socket(@_) || return;
	return http_end($s);
}

sub cert {
	my $s = get_socket(@_) || return;
	return $s->dump_peer_certificate();
}

sub get_socket {
	my ($host) = @_;
	return http_get(
		'/', start => 1, PeerAddr => '127.0.0.1:' . port(8080),
		SSL => 1,
		SSL_hostname => $host,
	);
}

###############################################################################
