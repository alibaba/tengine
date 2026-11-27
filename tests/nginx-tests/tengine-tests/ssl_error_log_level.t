#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for the log level of client SSL errors, http module:
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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl openssl:1.1.1 socket_ssl_sni/)
	->has_daemon('openssl');

$t->plan(20);

my $config = <<'EOF';

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    # handshake level inheritance

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;
    ssl_protocols TLSv1.3;

    server {
        listen       127.0.0.1:8443 ssl default_server;
        server_name  localhost;

        error_log %%TESTDIR%%/default.log info;

        location / {
            return 200 "ok";
        }
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  raised;

        ssl_handshake_error_log_level error;

        error_log %%TESTDIR%%/sni.log info;

        location / {
            return 200 "ok";
        }
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_handshake_error_log_level error;

        error_log %%TESTDIR%%/raised.log info;

        location / {
            return 200 "ok";
        }
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

$t->run();

###############################################################################

my $read_re = qr/SSL_read\(\) failed.*reset by peer/;
my $hs_reset_re = qr/SSL_do_handshake\(\) failed.*reset by peer/;
my $hs_proto_re = qr/SSL_do_handshake\(\) failed \(SSL:/;

# peer resets an established connection: never raised

reset_established(8443);

like(wait_log('default.log', $read_re), qr/\[info\].*$read_re/,
	'established reset - info');
unlike(read_log('default.log'), qr/\[error\].*$read_re/,
	'established reset - no error');

reset_established(8444);

like(wait_log('raised.log', $read_re), qr/\[info\].*$read_re/,
	'established reset - info with raised level');
unlike(read_log('raised.log'), qr/\[error\].*$read_re/,
	'established reset - no error with raised level');

# peer resets the connection in the middle of the handshake

reset_handshake(8443);

like(wait_log('default.log', $hs_reset_re), qr/\[info\].*$hs_reset_re/,
	'handshake reset - info');

reset_handshake(8444);

like(wait_log('raised.log', $hs_reset_re), qr/\[error\].*$hs_reset_re/,
	'handshake reset - raised');

# protocol level handshake failure

bad_protocol(8443, 'localhost');

like(wait_log('default.log', $hs_proto_re), qr/\[info\].*$hs_proto_re/,
	'handshake failure - info');

bad_protocol(8444, 'localhost');

like(wait_log('raised.log', $hs_proto_re), qr/\[error\].*$hs_proto_re/,
	'handshake failure - raised');

# virtual server selected by SNI applies its own level

bad_protocol(8443, 'raised');

like(wait_log('sni.log', $hs_proto_re), qr/\[error\].*$hs_proto_re/,
	'handshake failure - raised by sni');
is(scalar(() = read_log('default.log') =~ /$hs_proto_re/g), 1,
	'handshake failure - not in default log');

# TLS record errors after the handshake also keep their native level.

my $record_re = qr/SSL_read\(\) failed \(SSL:/;
for my $port (8443, 8444) {
	my $name = $port == 8443 ? 'default.log' : 'raised.log';
	bad_record($port);
	like(wait_log($name, $record_re), qr/\[info\].*$record_re/,
		"established TLS error - info on $port");
	unlike(read_log($name), qr/\[error\].*$record_re/,
		"established TLS error - no error on $port");
}

# Parent-level inheritance and server-level overrides.

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

	my $s = http('', start => 1, SSL => 1,
		PeerAddr => '127.0.0.1:' . port($port))
		or die "Can't establish TLS connection\n";

	# let the server finish the handshake before the reset

	select undef, undef, undef, 0.5;

	reset_close($s);
}

sub bad_record {
	my ($port) = @_;

	my $s = http('', start => 1, SSL => 1,
		PeerAddr => '127.0.0.1:' . port($port))
		or die "Can't establish TLS connection\n";
	select undef, undef, undef, 0.5;

	# Duplicate the fd without SSL wrapping and inject an invalid ciphertext.

	open my $raw, '+<&', $s or die "Can't duplicate socket: $!\n";
	syswrite($raw, "\x17\x03\x03\x00\x20" . "\x00" x 32)
		or die "Can't write TLS record: $!\n";
	select undef, undef, undef, 0.2;
	$s->close(SSL_no_shutdown => 1);
}

sub reset_handshake {
	my ($port) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . port($port)
	) or die "Can't connect to nginx: $!\n";

	# a truncated ClientHello record, the server waits for the rest

	$s->syswrite("\x16\x03\x01\x00\x80\x01\x00\x00\x7c\x03\x03");

	select undef, undef, undef, 0.5;

	reset_close($s);
}

sub bad_protocol {
	my ($port, $host) = @_;

	http("GET / HTTP/1.0\nHost: $host\n\n",
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host,
		SSL_version => 'TLSv1_2');
}

sub reset_close {
	my ($s) = @_;

	setsockopt($s, SOL_SOCKET, SO_LINGER, pack('ii', 1, 0))
		or die "Can't enable abortive close: $!\n";

	if ($s->isa('IO::Socket::SSL')) {
		$s->close(SSL_no_shutdown => 1);
	} else {
		$s->close();
	}
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
