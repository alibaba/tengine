#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 backend returning response with trailers.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;

        proxy_http_version 2;
        proxy_pass_trailers on;

        add_trailer X ""; # force chunked encoding

        location / {
            proxy_pass http://127.0.0.1:8081;
        }

        location /nobuffering {
            proxy_pass http://127.0.0.1:8081/;
            proxy_buffering off;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        add_header  Trailer "X-Trailer, X-Another";
        add_trailer X-Trailer foo;
        add_trailer X-Another bar;

        location / { }
    }
}

EOF

$t->write_file('index.html', 'SEE-THIS');
$t->try_run('no proxy_http_version 2')->plan(9);

###############################################################################

like(get('/'), qr/SEE-THIS.*X-Trailer: foo.*bar/si, 'trailers');
like(get('/nobuffering'), qr/SEE-THIS.*X-Trailer: foo.*bar/si,
	'trailers nobuffering');

# HTTP/2

my ($s, $sid, $frames, $frame);
$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/', },
	{ name => ':authority', value => 'localhost' },
	{ name => 'te', value => 'trailers', mode => 2 }]});

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

$frame = shift @$frames;
is($frame->{headers}->{':status'}, 200, 'h2 header');
is($frame->{flags}, 4, 'h2 header flags');

$frame = shift @$frames;
is($frame->{data}, 'SEE-THIS', 'h2 data');
is($frame->{flags}, 0, 'h2 data flags');

$frame = shift @$frames;
is($frame->{headers}->{'x-trailer'}, 'foo', 'h2 trailer');
is($frame->{headers}->{'x-another'}, 'bar', 'h2 trailer 2');
is($frame->{flags}, 5, 'h2 trailer flags');

###############################################################################

sub get {
	my ($uri) = @_;
	http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: te, close
TE: trailers

EOF
}

###############################################################################
