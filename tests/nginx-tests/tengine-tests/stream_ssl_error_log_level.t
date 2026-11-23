#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for the log level of client SSL errors, stream module:
# a peer reset on an established connection keeps the native info level,
# "ssl_handshake_error_log_level" only raises errors during the handshake.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ SOL_SOCKET SO_LINGER /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl openssl:1.1.1 socket_ssl_sni/)
	->has_daemon('openssl');

$t->plan(14);

my $config = <<'EOF';

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    # handshake level inheritance

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;
    ssl_protocols TLSv1.3;

    server {
        listen       127.0.0.1:8443 ssl default_server;
        server_name  localhost;

        error_log %%TESTDIR%%/default.log info;

        proxy_pass   127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  raised;

        ssl_handshake_error_log_level error;

        error_log %%TESTDIR%%/sni.log info;

        proxy_pass   127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8444 ssl;

        ssl_handshake_error_log_level error;

        error_log %%TESTDIR%%/raised.log info;

        proxy_pass   127.0.0.1:8081;
    }
}

EOF

$t->write_file_expand('nginx.conf', $config);

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

# the backend is never accepted, so proxied connections are kept open

my $backend = IO::Socket::INET->new(
	Proto => 'tcp',
	LocalAddr => '127.0.0.1:' . port(8081),
	Listen => 16,
	Reuse => 1
) or die "Can't create listening socket: $!\n";

$t->run();

###############################################################################

my $read_re = qr/SSL_read\(\) failed.*reset by peer/;
my $hs_proto_re = qr/SSL_do_handshake\(\) failed \(SSL:/;

# peer resets an established connection: never raised

reset_established(8443);

like(wait_log('default.log', $read_re), qr/\[info\].*$read_re/,
	'established reset - info');

reset_established(8444);

like(wait_log('raised.log', $read_re), qr/\[info\].*$read_re/,
	'established reset - info with raised level');
unlike(read_log('raised.log'), qr/\[error\].*$read_re/,
	'established reset - no error with raised level');

# protocol level handshake failure

bad_protocol(8443, 'localhost');

like(wait_log('default.log', $hs_proto_re), qr/\[info\].*$hs_proto_re/,
	'handshake failure - info');
unlike(read_log('default.log'), qr/\[error\].*SSL_/,
	'default - no error');

bad_protocol(8444, 'localhost');

like(wait_log('raised.log', $hs_proto_re), qr/\[error\].*$hs_proto_re/,
	'handshake failure - raised');

# virtual server selected by SNI applies its own level

bad_protocol(8443, 'raised');

like(wait_log('sni.log', $hs_proto_re), qr/\[error\].*$hs_proto_re/,
	'handshake failure - raised by sni');
is(scalar(() = read_log('default.log') =~ /$hs_proto_re/g), 1,
	'handshake failure - not in default log');

for my $level ('info', 'notice', 'warn') {
	$t->stop();
	my $inherited = $config;
	$inherited =~ s/# handshake level inheritance/ssl_handshake_error_log_level $level;/;
	$inherited =~ s/(default|raised|sni)\.log/$level-$1.log/g;
	$t->write_file_expand('nginx.conf', $inherited)->run();
	bad_protocol(8443, 'localhost');
	like(wait_log("$level-default.log", $hs_proto_re),
		qr/\[$level\].*$hs_proto_re/, "handshake level inherited - $level");
	bad_protocol(8444, 'localhost');
	like(wait_log("$level-raised.log", $hs_proto_re),
		qr/\[error\].*$hs_proto_re/, "server overrides inherited level - $level");
}

###############################################################################

sub reset_established {
	my ($port) = @_;

	my $s = IO::Socket::SSL->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port($port),
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
	) or die "Can't establish TLS connection: $IO::Socket::SSL::SSL_ERROR\n";

	# let the server finish the handshake before the reset

	select undef, undef, undef, 0.5;

	setsockopt($s, SOL_SOCKET, SO_LINGER, pack('ii', 1, 0))
		or die "Can't enable abortive close: $!\n";
	$s->close(SSL_no_shutdown => 1);
}

sub bad_protocol {
	my ($port, $host) = @_;

	IO::Socket::SSL->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port($port),
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_hostname => $host,
		SSL_version => 'TLSv1_2',
		Timeout => 3,
	);
}

sub wait_log {
	my ($name, $re) = @_;

	my $log = '';

	for (1 .. 50) {
		$log = read_log($name);
		last if $log =~ $re;
		select undef, undef, undef, 0.1;
	}

	return $log;
}

sub read_log {
	my ($name) = @_;

	open my $fh, '<', "$d/$name" or return '';
	local $/;
	return <$fh>;
}

###############################################################################
