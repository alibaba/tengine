#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx limit_req module.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=one:10m   rate=2r/s;
    limit_req_zone  $binary_remote_addr  zone=long:10m  rate=2r/s;
    limit_req_zone  $binary_remote_addr  zone=fast:10m  rate=1000r/s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            limit_req    zone=one  burst=1  nodelay;
        }
        location /long {
            limit_req    zone=long  burst=5;
        }
        location /fast {
            limit_req    zone=fast  burst=1;
        }
    }
}

EOF

$t->write_file('test1.html', 'XtestX');
$t->write_file('long.html', "1234567890\n" x (1 << 16));
$t->write_file('fast.html', 'XtestX');
$t->run();

###############################################################################

like(http_get('/test1.html'), qr/^HTTP\/1.. 200 /m, 'request');
http_get('/test1.html');
like(http_get('/test1.html'), qr/^HTTP\/1.. 503 /m, 'request rejected');
http_get('/test1.html');
http_get('/test1.html');

# Second request will be delayed by limit_req, make sure it isn't truncated.
# The bug only manifests itself if buffer will be filled, so sleep for a while
# before reading response.

my $l1 = length(http_get('/long.html'));
my $l2 = length(http_get('/long.html', sleep => 0.6));
is($l2, $l1, 'delayed big request not truncated');

# make sure rejected requests are not counted, and access is again allowed
# after 1/rate seconds

like(http_get('/test1.html'), qr/^HTTP\/1.. 200 /m, 'rejects not counted');

# make sure negative excess values are handled properly

http_get('/fast.html');
select undef, undef, undef, 0.1;
like(http_get('/fast.html'), qr/^HTTP\/1.. 200 /m, 'negative excess');

###############################################################################
