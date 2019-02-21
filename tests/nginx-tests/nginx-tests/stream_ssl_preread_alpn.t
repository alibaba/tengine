#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream_ssl_preread module, ALPN preread.

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

my $t = Test::Nginx->new()->has(qw/stream stream_map stream_ssl_preread/)
	->has(qw/stream_ssl stream_return/)->has_daemon('openssl')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    map $ssl_preread_alpn_protocols $name {
        ""       127.0.0.1:8093;
        default  $ssl_preread_alpn_protocols;
    }

    upstream foo {
        server 127.0.0.1:8091;
    }

    upstream bar {
        server 127.0.0.1:8092;
    }

    upstream foo,bar {
        server 127.0.0.1:8093;
    }

    ssl_preread  on;

    server {
        listen       127.0.0.1:8081;
        proxy_pass   $name;
    }

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8091 ssl;
        listen       127.0.0.1:8092 ssl;
        listen       127.0.0.1:8093 ssl;
        ssl_preread  off;
        return       $server_port;
    }
}

EOF

eval { require IO::Socket::SSL; die if $IO::Socket::SSL::VERSION < 1.56; };
plan(skip_all => 'IO::Socket::SSL version >= 1.56 required') if $@;

eval { IO::Socket::SSL->can_alpn() or die; };
plan(skip_all => 'IO::Socket::SSL with OpenSSL ALPN support required') if $@;

eval { exists &Net::SSLeay::P_alpn_selected or die; };
plan(skip_all => 'Net::SSLeay with OpenSSL ALPN support required') if $@;

$t->plan(5);

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
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

my ($p1, $p2, $p3) = (port(8091), port(8092), port(8093));

is(get_ssl(8081, 'foo'), $p1, 'alpn');
is(get_ssl(8081, 'foo'), $p1, 'alpn again');

is(get_ssl(8081, 'bar'), $p2, 'alpn 2');
is(get_ssl(8081, 'bar'), $p2, 'alpn 2 again');

is(get_ssl(8081, 'foo', 'bar'), $p3, 'alpn many');

get_ssl(8081, '');

###############################################################################

sub get_ssl {
	my ($port, @alpn) = @_;
	my $s = stream('127.0.0.1:' . port($port));

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
