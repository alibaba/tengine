#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3, sending ACK frames on congested network.

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
	->has_daemon('openssl')->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

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

# rough estimate to fill initial congestion window
$t->write_file('index.html', 'xSEE-THISx' x 1300);

###############################################################################

my ($s, $sid, $frames, $frame);

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream();

select undef, undef, undef, 0.2;

# expect PING acknowledgment to ignore congestion control
# while keeping the in-flight bytes counter high on server

$s->{send_ack} = 0;
$s->ping();
my $largest = $s->{pn}[0][3];

while (1) {
	my $rcvd = $s->read(all => [{ type => 'ACK' }], wait => 0.2);
	push @$frames, $_ for @$rcvd;

	($frame) = grep { $_->{type} eq "ACK" } @$rcvd;
	last unless $frame;
	last if $frame->{'largest'} == $largest;
};

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.0');

is($frame->{'largest'}, $largest, 'PING acked');

}

# make sure the requested stream is fully received

$s->{send_ack} = 1;

push @$frames, $_ for @{$s->read(all => [{ sid => $sid, fin => 1 }])};

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{'length'}, 13000, 'body');

###############################################################################
