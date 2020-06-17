#!/usr/bin/perl

# (C) diaoliang

# Tests for nginx limit_req module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

#select STDERR; $| = 1;
#select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http limit_req/)->plan(27);


$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;


events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=one:3m   rate=1r/s;
    limit_req_zone  $binary_remote_addr $uri  zone=two:3m   rate=1r/s;
    limit_req_zone  $binary_remote_addr $uri  $args zone=thre:3m   rate=1r/s;
    limit_req_zone  $binary_remote_addr  zone=long:3m   rate=1r/s;
    limit_req_zone  $binary_remote_addr  zone=fast:3m  rate=1000r/s;

    limit_req_zone  $uri  zone=inter:3m  rate=1r/s;

    geo $white_ip1 {
        default 0;
        127.0.8.9 1;
    }

    geo $white_ip2 {
        default 0;
        127.0.0.0/24 1;
    }
    limit_req_whitelist  geo_var_name=white_ip1 geo_var_value=1;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        location / {
            limit_req    zone=one nodelay burst=5;
            limit_req    zone=two nodelay forbid_action=@t;
            limit_req    zone=thre nodelay burst=3;
        }

        location @t {
           rewrite ^  /t.html;
        }

        location /one {
            limit_req    zone=one nodelay;
        }
        location /two {
            limit_req    zone=two nodelay;
        }
        location /thre {
            limit_req    zone=thre nodelay;
        }
        location /long {
            limit_req    zone=long nodelay burst=5;
        }
        location /fast {
            limit_req    zone=fast nodelay burst=1;
        }

        location /white {
            limit_req_whitelist  geo_var_name=white_ip2 geo_var_value=1;
            limit_req    zone=one nodelay;
        }

        location /inter {
              expires 1h;
              limit_req    zone=inter nodelay forbid_action=/t.html;
        }

        location /t.html {
            expires 1h;
        }
    }
}

EOF

$t->write_file('one.html', 'XtestX');
$t->write_file('one2.html', 'XtestX');
$t->write_file('two.html', 'XtestX');
$t->write_file('two2.html', 'XtestX');
$t->write_file('thre.html', 'XtestX');
$t->write_file('long.html', "1234567890\n" x (1 << 16));
$t->write_file('fast.html', 'XtestX');
$t->write_file('collect1.html', 'collect1');
$t->write_file('collect2.html', 'collect2');
$t->write_file('t.html', 'test');
$t->write_file('white.html', 'test');
$t->write_file('inter.html', 'test');
$t->run();

###############################################################################
like(http_get('/inter.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/inter.html'), qr/test/m, 'request accept');

like(http_get('/one.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/two.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/thre.html'), qr/^HTTP\/1.. 200 /m, 'request accept');

http_get('/one.html');
like(http_get('/one2.html'), qr/^HTTP\/1.. 503 /m, 'request rejected');
http_get('/two.html');
like(http_get('/two2.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
http_get('/thre.html?a=3');
like(http_get('/thre.html?a=5'), qr/^HTTP\/1.. 200 /m, 'request accept');
http_get('/thre.html?a=4');
like(http_get('/thre.html?a=4'), qr/^HTTP\/1.. 503 /m, 'request rejected');
http_get('/thre.html');
# Fixme: tengine-2.3.x removed the logic that skip counting
# with any empty value variable in limit_req_zone.
like(http_get('/thre.html'), qr/^HTTP\/1.. 503 /m, 'request rejected');

# Second request will be delayed by limit_req, make sure it isn't truncated.
# The bug only manifests itself if buffer will be filled, so sleep for a while
# before reading response.

my $l1 = length(http_get('/long.html'));
my $l2 = length(http_get('/long.html', sleep => 1.1));
is($l2, $l1, 'delayed big request not truncated');

# make sure negative excess values are handled properly

http_get('/fast.html');
select (undef, undef, undef, 0.1);
like(http_get('/fast.html'), qr/^HTTP\/1.. 200 /m, 'negative excess');

#whitelist
like(http_get('/white.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/white.html'), qr/^HTTP\/1.. 200 /m, 'request accept');

#test mutil condition
like(http_get('/collect2.html?a=3'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/collect1.html?a=4'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/collect1.html?a=4', sleep => 1.1), qr/^HTTP\/1.. 200 /m, 'request accept');


like(http_get('/collect1.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/collect2.html'), qr/^HTTP\/1.. 200 /m, 'request accept');

like(http_get('/collect1.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/collect1.html'), qr/test/m, 'request accept');


$t->stop();


##########################################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;


events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $binary_remote_addr  zone=one:3m   rate=1r/s;

    limit_req    zone=one;
    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_req off;
        }

        location /limit {
        }
    }
}

EOF
$t->write_file('switch.html', 'switch');
$t->write_file('limit.html', 'limit');

$t->run();

#switch test
like(http_get('/switch.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/switch.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/switch.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/switch.html'), qr/^HTTP\/1.. 200 /m, 'request accept');

like(http_get('/limit.html'), qr/^HTTP\/1.. 200 /m, 'request accept');
like(http_get('/limit.html'), qr/^HTTP\/1.. 503 /m, 'request rejected');

$t->stop();
