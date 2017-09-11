#!/usr/bin/perl

# Copyright (C) 2017 Alibaba Group Holding Limited

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(1);
$t->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
}

http {

    limit_req_zone $binary_remote_addr zone=one:10m rate=1r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /slab_stat {
            slab_stat;
        }
    }
}

EOF

###############################################################################

$t->run();

my $status = http_get("/slab_stat");

like($status, qr/shared memory/m,
     'slab_stat returns information about shared memory usage');

print "--- debug for verbose mode ---\n",
      "$status",
      "------------------------------\n";

$t->stop();
