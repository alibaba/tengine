#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 trailers.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2/)->plan(22)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        location / {
            add_trailer X-Var $host;
        }

        location /continuation {
            # many trailers to send in parts
            add_trailer X-LongHeader $arg_h;
            add_trailer X-LongHeader $arg_h;
            add_trailer X-LongHeader $arg_h;
            add_trailer X-LongHeader $arg_h;
            add_trailer X-LongHeader $arg_h;
        }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->write_file('empty', '');
$t->write_file('continuation', 'SEE-THIS');
$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

is(@$frames, 3, 'frames');

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'header');
is($frame->{headers}->{'x-var'}, undef, 'header not trailer');
is($frame->{flags}, 4, 'header flags');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'data');
is($frame->{flags}, 0, 'data flags');

$frame = shift @$frames;
is($frame->{headers}->{'x-var'}, 'localhost', 'trailer');
is($frame->{flags}, 5, 'trailer flags');

# with zero content-length

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/empty' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

is(@$frames, 2, 'no data - frames');

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'no data - header');
is($frame->{flags}, 4, 'no data - header flags');

$frame = shift @$frames;
is($frame->{headers}->{'x-var'}, 'localhost', 'no data - trailer');
is($frame->{flags}, 5, 'no data - trailer flags');

# CONTINUATION in response trailers

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/continuation?h=' . 'x' x 4000 });
$frames = $s->read(all => [{ sid => $sid, type => 'CONTINUATION' }]);
@$frames = grep { $_->{type} =~ "HEADERS|CONTINUATION|DATA" } @$frames;

is(@$frames, 4, 'continuation - frames');

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'continuation - header');
is($frame->{flags}, 4, 'continuation - header flags');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'continuation - data');
is($frame->{flags}, 0, 'continuation - data flags');

$frame = shift @$frames;
is($frame->{type}, 'HEADERS', 'continuation - trailer');
is($frame->{flags}, 1, 'continuation - trailer flags');

$frame = shift @$frames;
is($frame->{type}, 'CONTINUATION', 'continuation - trailer continuation');
is($frame->{flags}, 4, 'continuation - trailer continuation flags');

###############################################################################
