#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for various TLSv1.3 ciphers in QUIC.

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
	->has_daemon('openssl')->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        location / {
            add_header x-cipher  $ssl_cipher;
            add_header x-ciphers $ssl_ciphers;
        }
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

$t->write_file('index.html', '');
$t->run();

###############################################################################

is(get("\x13\x01"), 'TLS_AES_128_GCM_SHA256', 'TLS_AES_128_GCM_SHA256');
is(get("\x13\x02"), 'TLS_AES_256_GCM_SHA384', 'TLS_AES_256_GCM_SHA384');
is(get("\x13\x03"), 'TLS_CHACHA20_POLY1305_SHA256',
	'TLS_CHACHA20_POLY1305_SHA256');

# TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256

is(get("\x13\x02\x13\x01"), 'TLS_AES_256_GCM_SHA384', 'ciphers many');

# prefer TLS_AES_128_CCM_SHA256 with fallback to GCM,
# the cipher is enabled by default in some distributions

like(get("\x13\x04\x13\x01"), qr/TLS_AES_128_[GC]CM_SHA256/,
	'TLS_AES_128_CCM_SHA256');

###############################################################################

sub get {
	my ($ciphers) = @_;
	my $s = Test::Nginx::HTTP3->new(8980, ciphers => $ciphers);
	my $frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{'x-cipher'};
}

###############################################################################
