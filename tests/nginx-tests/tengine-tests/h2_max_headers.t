#!/usr/bin/perl

# Tests for HTTP/2 enforcement of the http core max_headers directive.
#
# Regression test for the "HTTP/2 Bomb" class of attack
# (HPACK indexed-reference amplification):
# https://blog.calif.io/p/codex-discovered-a-hidden-http2-bomb
#
# An attacker inserts a single header into the HPACK dynamic table,
# then emits thousands of one-byte indexed references to it.  The
# byte-based large_client_header_buffers limit never fires because
# each reference adds only a few decoded bytes, while the server
# allocates a full header slot per reference.  max_headers caps the
# per-request field count and trips the request with 400-class status
# before the amplification can take hold.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 rewrite/)->plan(5)
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

        max_headers 50;

        location / {
            return 200 ok;
        }
    }

    server {
        listen       127.0.0.1:8081 http2;
        server_name  localhost;

        # default max_headers (1000) should still reject the bomb

        location / {
            return 200 ok;
        }
    }
}

EOF

$t->run();

###############################################################################

# 1) baseline: a normal request with a handful of headers is accepted.

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ headers => [
	{ name => ':method',    value => 'GET',       mode => 0 },
	{ name => ':scheme',    value => 'http',      mode => 0 },
	{ name => ':path',      value => '/',         mode => 0 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'x-a',        value => '1',         mode => 2 },
	{ name => 'x-b',        value => '2',         mode => 2 },
]});
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
is($frame->{headers}->{':status'}, 200, 'baseline - 200 OK');

# 2) the HPACK indexed-reference bomb.
#
# First field: literal-with-incremental-indexing.  This both sends the
# header and parks one (name, value) entry in the dynamic table at the
# first dynamic index, one byte of wire encoding per later use.
#
# Following fields: 60 indexed references to that same entry.  Each
# reference is one wire byte, but every one of them is a fresh header
# field on the server side and counts against max_headers.  With the
# limit set to 50, the 51st field must trip the cap.

my @bomb;
push @bomb, { name => ':method',    value => 'GET',       mode => 0 };
push @bomb, { name => ':scheme',    value => 'http',      mode => 0 };
push @bomb, { name => ':path',      value => '/',         mode => 0 };
push @bomb, { name => ':authority', value => 'localhost', mode => 1 };
push @bomb, { name => 'x-bomb',     value => 'v',         mode => 1 };
push @bomb, { name => 'x-bomb',     value => 'v',         mode => 0 } for 1 .. 60;

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ headers => \@bomb });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
isnt($frame && $frame->{headers}->{':status'}, '200',
	'bomb - request rejected, not 200');
like($frame && $frame->{headers}->{':status'}, qr/^4\d\d$/,
	'bomb - 4xx status returned');

# 3) the default cap (1000) still rejects an oversized bomb on a
# server that does not set max_headers explicitly.

my @big;
push @big, { name => ':method',    value => 'GET',       mode => 0 };
push @big, { name => ':scheme',    value => 'http',      mode => 0 };
push @big, { name => ':path',      value => '/',         mode => 0 };
push @big, { name => ':authority', value => 'localhost', mode => 1 };
push @big, { name => 'x-bomb',     value => 'v',         mode => 1 };
push @big, { name => 'x-bomb',     value => 'v',         mode => 0 } for 1 .. 1100;

$s = Test::Nginx::HTTP2->new(port(8081));
$sid = $s->new_stream({ headers => \@big });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
isnt($frame && $frame->{headers}->{':status'}, '200',
	'default cap - request rejected, not 200');
like($frame && $frame->{headers}->{':status'}, qr/^4\d\d$/,
	'default cap - 4xx status returned');

###############################################################################
