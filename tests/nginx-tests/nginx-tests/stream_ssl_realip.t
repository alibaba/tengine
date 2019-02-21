#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream realip module, server side proxy protocol with ssl.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL::SSL_VERIFY_NONE(); };
plan(skip_all => 'IO::Socket::SSL too old') if $@;

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_realip/)
	->has(qw/stream_ssl/)->has_daemon('openssl')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen      127.0.0.1:8083 proxy_protocol ssl;
        return      $proxy_protocol_addr:$proxy_protocol_port;
    }

    server {
        listen      127.0.0.1:8086 proxy_protocol ssl;
        listen      [::1]:%%PORT_8086%% proxy_protocol ssl;
        return      "$remote_addr:$remote_port:
                     $realip_remote_addr:$realip_remote_port";

        set_real_ip_from ::1;
        set_real_ip_from 127.0.0.2;
    }

    server {
        listen      127.0.0.1:8087;
        proxy_pass  [::1]:%%PORT_8086%%;
    }

    server {
        listen      127.0.0.1:8088 proxy_protocol ssl;
        listen      [::1]:%%PORT_8088%% proxy_protocol ssl;
        return      "$remote_addr:$remote_port:
                     $realip_remote_addr:$realip_remote_port";

        set_real_ip_from 127.0.0.1;
        set_real_ip_from ::2;
    }

    server {
        listen      127.0.0.1:8089;
        proxy_pass  [::1]:%%PORT_8088%%;
    }
}

EOF

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

$t->try_run('no inet6 support')->plan(6);

###############################################################################

is(pp_get(8083, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1:1234', 'server');

like(pp_get(8086, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(\Q127.0.0.1:\E\d+):\s+\1$/, 'server ipv6 realip - no match');

like(pp_get(8087, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/\Q192.0.2.1:1234:\E\s+\Q::1:\E\d+/, 'server ipv6 realip');

like(pp_get(8088, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/\Q192.0.2.1:1234:\E\s+\Q127.0.0.1:\E\d+/, 'server ipv4 realip');

like(pp_get(8089, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(::1:\d+):\s+\1$/, 'server ipv4 realip - no match');

like(pp_get(8088, "PROXY UNKNOWN TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(\Q127.0.0.1:\E\d+):\s+\1$/, 'server unknown');

###############################################################################

sub pp_get {
	my ($port, $proxy) = @_;

	my $s = stream(PeerPort => port($port));
	$s->write($proxy);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		IO::Socket::SSL->start_SSL($s->{_socket},
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
