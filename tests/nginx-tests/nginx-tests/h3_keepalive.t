#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol, keepalive directives.

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
	->has_daemon('openssl')->plan(15)
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

        keepalive_requests 2;

        location / { }
    }

    server {
        listen       127.0.0.1:%%PORT_8981_UDP%% quic;
        server_name  localhost;

        keepalive_timeout 0;

        location / { }
    }

    server {
        listen       127.0.0.1:%%PORT_8982_UDP%% quic;
        server_name  localhost;

        keepalive_time 1s;

        add_header X-Conn $connection_requests:$connection_time;

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

$t->write_file('index.html', 'SEE-THIS');

$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

# max requests limited

$s = Test::Nginx::HTTP3->new();
$frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive requests 1');

$frames = $s->read(all => [
	{ sid => $s->new_stream(), fin => 1 },
	{ type => 'GOAWAY' }
]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive requests 2');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{sid}, 3, 'keepalive requests - GOAWAY stream type');
is($frame->{last_sid}, 8, 'keepalive requests - GOAWAY last stream');

# keepalive_timeout 0
# currently, keepalive timer is set before reading 1st request
# and there is no special handling for zero value timeout

$s = Test::Nginx::HTTP3->new(8981);

TODO: {
todo_skip 'keepalive_timeout 0', 2 unless $s;

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive_timeout 0');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'keepalive_timeout 0 - GOAWAY');

}

# keepalive_time

$s = Test::Nginx::HTTP3->new(8982);
$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive time request');
like($frame->{headers}->{'x-conn'}, qr/^1:0/, 'keepalive time variables');

$frames = $s->read(all => [{ type => 'GOAWAY' }], wait => 0.5);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame, undef, 'keepalive time - no GOAWAY yet');

select undef, undef, undef, 1.1;

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'keepalive time request 2');
like($frame->{headers}->{'x-conn'}, qr/^2:[^0]/, 'keepalive time variables 2');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{sid}, 3, 'keepalive time limit - GOAWAY stream type');
is($frame->{last_sid}, 8, 'keepalive time limit - GOAWAY last stream');

# graceful shutdown in idle state

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream();

$t->reload();

$frames = $s->read(all => [{ type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame->{sid}, 3, 'graceful shutdown - GOAWAY stream type');
is($frame->{last_sid}, 4, 'graceful shutdown - GOAWAY last stream');

###############################################################################
