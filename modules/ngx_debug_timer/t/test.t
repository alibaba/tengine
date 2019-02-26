#!/usr/bin/perl

# Copyright (C) 2018 Alibaba Group Holding Limited

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

        location /debug_timer {
            debug_timer;
        }
    }
}

EOF

###############################################################################

$t->run();

my $status = http_get("/debug_timer");

like($status, qr#200 OK#, 'debug_timer returns information of timers and related events');

print "--- debug for verbose mode ---\n",
      "$status",
      "------------------------------\n";

$t->stop();
