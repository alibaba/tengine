#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# limit_req based tests for limit_conn module with complex keys.

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

my $t = Test::Nginx->new()->has(qw/http proxy limit_conn limit_req shmem/)
	->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone   $binary_remote_addr$arg_r  zone=req:1m rate=30r/m;
    limit_req_zone   $binary_remote_addr        zone=re2:1m rate=30r/m;
    limit_conn_zone  $binary_remote_addr$arg_c  zone=conn:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_conn conn 1;
        }

        location /w {
            limit_conn conn 1;
            proxy_pass http://127.0.0.1:8080/req2;
        }

        location /req {
            limit_req  zone=req burst=2;
        }

        location /req2 {
            limit_req  zone=re2 burst=2;
        }
    }
}

EOF

$t->run();

###############################################################################

my $s;

# charge limit_req

http_get('/req');

# limit_req tests

$s = http_get('/req', start => 1);
ok(!IO::Select->new($s)->can_read(0.1), 'limit_req same key');

$s = http_get('/req?r=2', start => 1);
ok(IO::Select->new($s)->can_read(0.1), 'limit_req different key');

# limit_conn tests

http_get('/req2');

$s = http_get('/w', start => 1);
select undef, undef, undef, 0.2;

like(http_get('/'), qr/^HTTP\/1.. 503 /, 'limit_conn same key');
unlike(http_get('/?c=2'), qr/^HTTP\/1.. 503 /, 'limit_conn different key');

###############################################################################
