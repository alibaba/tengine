#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for TLS early data with HTTP/3.

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
	->has_daemon('openssl')->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_early_data on;

    add_header X-Session $ssl_session_reused always;
    add_header X-Early   $ssl_early_data     always;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;
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

my $s = Test::Nginx::HTTP3->new(8980);
my $frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-session'}, '.', 'new session');

local $TODO = 'no TLSv1.3 sessions in LibreSSL' if $t->has_module('LibreSSL');

my $psk_list = $s->{psk_list};

$s = Test::Nginx::HTTP3->new(8980, psk_list => $psk_list, early_data => {},
	start_chain => 1);

TODO: {
local $TODO = 'no 0-RTT in OpenSSL compat layer'
	unless $t->has_module('OpenSSL [.0-9]+\+quic')
	or $t->has_feature('openssl:3.5.1') && $t->has_version('1.29.1')
	or $t->has_module('BoringSSL|AWS-LC')
	or $t->has_module('LibreSSL');

$frames = $s->read(all => [{ sid => 0, fin => 1 }]);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-session'}, 'r', 'reused session 0rtt');
is($frame->{headers}->{'x-early'}, '1', 'reused session is early');

}

# includes sending some initial 1-RTT data

$s->send_chain();

TODO: {
local $TODO = 'not yet'
	if $t->has_version('1.27.1') && !$t->has_version('1.27.4');

$frames = $s->read(all => [{ type => 'HANDSHAKE_DONE' }], wait => 0.5);

($frame) = grep { $_->{type} eq "HANDSHAKE_DONE" } @$frames;
ok($frame, '1rtt after discarding 0rtt');

}

$frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-session'}, 'r', 'reused session 1rtt');
is($frame->{headers}->{'x-early'}, undef, 'reused session not early');

###############################################################################
