#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl_alpn directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return/)
	->has_daemon('openssl')->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    log_format test $status;
    access_log %%TESTDIR%%/test.log test;

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen    127.0.0.1:8080 ssl;
        return    "X $ssl_alpn_protocol X";
        ssl_alpn  first second;
    }
}

EOF

eval { require IO::Socket::SSL; die if $IO::Socket::SSL::VERSION < 1.56; };
plan(skip_all => 'IO::Socket::SSL version >= 1.56 required') if $@;

eval { IO::Socket::SSL->can_alpn() or die; };
plan(skip_all => 'IO::Socket::SSL with OpenSSL ALPN support required') if $@;

eval { exists &Net::SSLeay::P_alpn_selected or die; };
plan(skip_all => 'Net::SSLeay with OpenSSL ALPN support required') if $@;

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

$t->try_run('no ssl_alpn')->plan(6);

###############################################################################

is(get_ssl('first'), 'X first X', 'alpn match');
is(get_ssl('wrong', 'first'), 'X first X', 'alpn many');
is(get_ssl('wrong', 'second'), 'X second X', 'alpn second');
is(get_ssl(), 'X  X', 'no alpn');

SKIP: {
$t->{_configure_args} =~ /LibreSSL ([\d\.]+)/;
skip 'LibreSSL too old', 2 if defined $1 and $1 lt '3.4.0';
$t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;
skip 'OpenSSL too old', 2 if defined $1 and $1 lt '1.1.0';

ok(!get_ssl('wrong'), 'alpn mismatch');

$t->stop();

like($t->read_file('test.log'), qr/500$/, 'alpn mismatch - log');

}

###############################################################################

sub get_ssl {
	my (@alpn) = @_;
	my $s = stream('127.0.0.1:' . port(8080));

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		IO::Socket::SSL->start_SSL($s->{_socket},
			SSL_alpn_protocols => [ @alpn ],
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

	return $s->read();
}

###############################################################################
