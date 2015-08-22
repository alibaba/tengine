#!/usr/bin/perl

# Copyright (C) 2015 Alibaba Group Holding Limited

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(1)
        ->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
}

http {
    server {
        listen       127.0.0.1:8080;

        location /debug_pool {
            debug_pool;
        }
    }
}

EOF

###############################################################################

$t->run();

my $status = http_get("/debug_pool");

like($status, qr/pid:\d+\nsize: *\d+ num: *\d+ cnum: *\d+ lnum: *\d+ \w+/,
     'debug_pool returns information about memory pool usage');

print "--- debug for verbose mode ---\n",
      "$status",
      "------------------------------\n";

$t->stop();
