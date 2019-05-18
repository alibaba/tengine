#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol, http2_max_requests directive.

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

my $t = Test::Nginx->new()->has(qw/http http_v2/)
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

        http2_max_requests 2;

        location / { }
    }
}

EOF

$t->write_file('index.html', '');
$t->run()->plan(5);

###############################################################################

my $s = Test::Nginx::HTTP2->new();
my $frames = $s->read(all => [{ sid => $s->new_stream(), fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'max requests');

$frames = $s->read(all => [{ type => 'GOAWAY' }], wait => 0.5)
	unless grep { $_->{type} eq "GOAWAY" } @$frames;

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
is($frame, undef, 'max requests - GOAWAY');

# max requests limited

my $sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }, { type => 'GOAWAY' }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'max requests limited');

($frame) = grep { $_->{type} eq "GOAWAY" } @$frames;
ok($frame, 'max requests limited - GOAWAY');
is($frame->{last_sid}, $sid, 'max requests limited - GOAWAY last stream');

###############################################################################
