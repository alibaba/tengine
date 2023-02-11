#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for worker_shutdown_timeout directive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_shutdown_timeout 10ms;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->run()->plan(1);

###############################################################################

my $s = http('', start => 1);

select undef, undef, undef, 0.2;

$t->reload();

if (IO::Select->new($s)->can_read(5)) {
	Test::Nginx::log_core('||', "select: can_read");
}

is(http_get('/', socket => $s) || '', '', 'worker_shutdown_timeout');

###############################################################################
