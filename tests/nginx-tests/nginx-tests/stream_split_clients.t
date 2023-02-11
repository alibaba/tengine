#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream split_client module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_split_clients stream_return/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    split_clients $connection $variant {
        51.2%  "first";
        10%    "second";
        *      "third";
    }

    server {
        listen  127.0.0.1:8080;
        return  $variant;
    }
}

EOF

$t->run();
$t->plan(1);

###############################################################################

# NB: split_clients distribution is a subject to implementation details

like(many('/', 20), qr/first: 12, second: 2, third: 6/, 'split');

###############################################################################

sub many {
	my ($uri, $count) = @_;
	my %dist;

	for (1 .. $count) {
		if (my $data = stream('127.0.0.1:' . port(8080))->read()) {
			$dist{$data} = 0 unless defined $data;
			$dist{$data}++;
		}
	}

	return join ', ', map { $_ . ": " . $dist{$_} } sort keys %dist;
}

###############################################################################
