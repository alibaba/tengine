#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for max headers limit in requests.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ LF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/);

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

        max_headers 5;

        location / { }
    }
}

EOF

$t->write_file('index.html', '');
$t->try_run('no max_headers')->plan(2);

###############################################################################

like(get('/', 5), qr/200 OK/, 'max headers');
like(get('/', 6), qr/400 Bad/, 'max headers reached');

###############################################################################

sub get {
	my ($uri, $count) = @_;
	my $extra = join LF, map { "X-Blah: $_" } (1 .. $count - 1);

	http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
$extra

EOF
}

###############################################################################
