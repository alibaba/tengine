#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 trailers.

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
	->has_daemon('openssl')->plan(8);

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
            add_trailer X-Var $host;
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

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('empty', '');
$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

is(@$frames, 3, 'frames');

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'header');
is($frame->{headers}->{'x-var'}, undef, 'header not trailer');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'data');

$frame = shift @$frames;
is($frame->{headers}->{'x-var'}, 'localhost', 'trailer');

# with zero content-length

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/empty' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

is(@$frames, 2, 'no data - frames');

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'no data - header');

$frame = shift @$frames;
is($frame->{headers}->{'x-var'}, 'localhost', 'no data - trailer');

###############################################################################
