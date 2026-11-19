#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for max headers limit in requests.

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

my $t = Test::Nginx->new()->has(qw/http http_v2/);

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
        max_headers 5;

        location / { }
    }
}

EOF

$t->write_file('index.html', '');
$t->try_run('no max_headers')->plan(2);

###############################################################################

is(get('/', 5), '200', 'max headers');
is(get('/', 6), '400', 'max headers reached');

###############################################################################

sub get {
	my ($uri, $count) = @_;

	my $h = [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/', mode => 0 },
		{ name => ':authority', value => 'localhost', mode => 1 }];

	push @$h, map {{ name => 'x-blah', value => $_, mode => 2 }}
		1 .. $count;

	my $s = Test::Nginx::HTTP2->new();
	my $sid = $s->new_stream({ headers => $h });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{':status'};
}

###############################################################################
