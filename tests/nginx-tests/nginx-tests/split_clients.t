#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for split_client module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http split_clients/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    split_clients $connection $variant {
        51.2%  ".one";
        10%    ".two";
        *      ".three";
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            index index${variant}.html;
        }
    }
}

EOF

$t->write_file('index.one.html', 'first');
$t->write_file('index.two.html', 'second');
$t->write_file('index.three.html', 'third');

$t->run();

###############################################################################

# NB: split_clients distribution is a subject to implementation details

like(many('/', 20), qr/first: 12, second: 2, third: 6/, 'split');

###############################################################################

sub many {
	my ($uri, $count) = @_;
	my %dist;

	for (1 .. $count) {
		if (http_get($uri) =~ /(first|second|third)/) {
			$dist{$1} = 0 unless defined $dist{$1};
			$dist{$1}++;
		}
	}

	return join ', ', map { $_ . ": " . $dist{$_} } sort keys %dist;
}

###############################################################################
