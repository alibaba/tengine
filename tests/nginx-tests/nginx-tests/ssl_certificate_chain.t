#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module with certificate chain.

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

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL::SSL_VERIFY_NONE(); };
plan(skip_all => 'IO::Socket::SSL too old') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl/)
	->has_daemon('openssl')->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_certificate_key end.key;
        ssl_certificate end.crt;
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate_key int.key;
        ssl_certificate int.crt;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate_key end.key;
        ssl_certificate end-int.crt;
    }
}

EOF

my $d = $t->testdir();

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

$t->write_file('ca.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha256
policy = myca_policy
serial = $d/certserial
default_days = 1
x509_extensions = myca_extensions

[ myca_policy ]
commonName = supplied

[ myca_extensions ]
basicConstraints = critical,CA:TRUE
EOF

foreach my $name ('root') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('int', 'end') {
	system("openssl req -new "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-subj /CN=int/ -in $d/int.csr -out $d/int.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for int: $!\n";

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/int.key -cert $d/int.crt "
	. "-subj /CN=end/ -in $d/end.csr -out $d/end.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for end: $!\n";

$t->write_file('end-int.crt',
	$t->read_file('end.crt') . $t->read_file('int.crt'));

$t->run();

###############################################################################

is(get_ssl_socket(port(8080)), undef, 'incomplete chain');
ok(get_ssl_socket(port(8081)), 'intermediate');
ok(get_ssl_socket(port(8082)), 'intermediate server');

###############################################################################

sub get_ssl_socket {
	my ($port) = @_;
	my ($s, $verify);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER(),
			SSL_ca_file => "$d/root.crt",
			SSL_verify_callback => sub {
				my ($ok) = @_;
				$verify = $ok;
				return $ok;
			},
			SSL_error_trap => sub { die $_[1] }
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $verify;
}

###############################################################################
