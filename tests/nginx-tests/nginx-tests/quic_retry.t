#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for QUIC address validation.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 cryptx/)
	->has_daemon('openssl')->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    quic_retry on;

    keepalive_timeout 3s;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        location / { }
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

$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

$s = Test::Nginx::HTTP3->new(8980);
$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'NEW_TOKEN' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 403, 'retry success');

is(unpack("H*", $s->retry_tag()), unpack("H*", $s->retry_verify_tag()),
	'retry integrity tag');

($frame) = grep { $_->{type} eq "NEW_TOKEN" } @$frames;
ok(my $new_token = $frame->{token}, 'new token received');
ok(my $retry_token = $s->retry_token(), 'retry token received');

# connection with new token

$s = Test::Nginx::HTTP3->new(8980, token => $new_token);
$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 403, 'new token success');

# connection with retry token, port won't match

$s = Test::Nginx::HTTP3->new(8980, token => $retry_token, probe => 1);
$frames = $s->read(all => [{ type => 'CONNECTION_CLOSE' }]);

($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
is($frame->{error}, 11, 'retry token invalid');

# connection with retry token, corrupted

substr($retry_token, 32) ^= "\xff";
$s = Test::Nginx::HTTP3->new(8980, token => $retry_token, probe => 1);
$frames = $s->read(all => [{ type => 'CONNECTION_CLOSE' }]);

($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
is($frame->{error}, 11, 'retry token decrypt error');

# resending client Initial packets after receiving a Retry packet
# to simulate server Initial packet loss triggering its retransmit,
# used to create extra nginx connections before 1bc204a3a (1.25.3),
# caught by CRYPTO stream mismatch among server Initial packets

$s = new_connection_resend();
$sid = $s->new_stream();

# would die on "bad inner" sanity check
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 403, 'resend initial');

###############################################################################

# expanded handshake version to send repetitive Initial packets

sub new_connection_resend {
	$s = Test::Nginx::HTTP3->new(8980, probe => 1);
	$s->{socket}->sysread($s->{buf}, 65527);
	# read token and updated connection IDs
	(undef, undef, $s->{token}) = $s->decrypt_retry($s->{buf});
	# apply connection IDs for new Initial secrets
	$s->retry(probe => 1);
	# send the second Initial packet
	$s->initial();
	# the rest of handshake, advancing key schedule
	$s->handshake();
	return $s;
}

###############################################################################
