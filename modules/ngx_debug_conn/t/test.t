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

        location /debug_conn {
            debug_conn;
        }
    }
}

EOF

###############################################################################

$t->run();

my $status = http_get("/debug_conn");

like($status, qr#uri: http://localhost/debug_conn#,
     'debug_conn returns information of ngx_cycle->connections[]');

print "--- debug for verbose mode ---\n",
      "$status",
      "------------------------------\n";

$t->stop();
