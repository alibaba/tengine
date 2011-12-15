#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for http variables.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy/)->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format cc "CC: $sent_http_cache_control";

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        access_log %%TESTDIR%%/cc.log cc;

        location / {
            return 200 OK;
        }

        location /set {
            add_header Cache-Control max-age=3600;
            add_header Cache-Control private;
            add_header Cache-Control must-revalidate;
            return 200 OK;
        }

        location /redefine {
            expires epoch;
            proxy_pass http://127.0.0.1:8080/set;
        }
    }
}

EOF

$t->run();

###############################################################################

http_get('/');
http_get('/redefine');

$t->stop();

my @log;

open LOG, $t->testdir() . '/cc.log'
	or die("Can't open nginx access log file.\n");

foreach my $line (<LOG>) {
	chomp $line;
	push @log, $line;
}

close LOG;

is(shift @log, 'CC: -', 'no header');
is(shift @log, 'CC: max-age=3600; private; must-revalidate', 'multi headers');

TODO:{
local $TODO = 'add hash checks';

is(shift @log, 'CC: no-cache', 'ignoring headers with (hash == 0)');
}

###############################################################################
