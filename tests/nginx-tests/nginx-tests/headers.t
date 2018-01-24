#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for headers module.

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

my $t = Test::Nginx->new()->has(qw/http/)->plan(25)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header   X-URI $uri;
        add_header   X-Always $uri always;
        expires      epoch;

        location /t1 {
        }

        location /nx {
        }

        location /epoch {
            expires epoch;
        }

        location /max {
            expires max;
        }

        location /off {
            expires off;
        }

        location /access {
            expires 2048;

            location /access_inner {
                # inherited from outer
            }
        }

        location /negative {
            expires -2048;
        }

        location /daily {
            expires @15h30m33s;
        }

        location /modified {
            expires modified 2048;
        }

        location /var {
            expires $arg_e;

            location /var_inner {
                # inherited from outer
            }

            location /var_modified {
                expires modified $arg_e;
            }
        }
    }
}

EOF

$t->write_file('t1', '');
$t->write_file('epoch', '');
$t->write_file('max', '');
$t->write_file('off', '');
$t->write_file('access', '');
$t->write_file('access_inner', '');
$t->write_file('negative', '');
$t->write_file('daily', '');
$t->write_file('modified', '');
$t->write_file('var', '');
$t->write_file('var_inner', '');
$t->write_file('var_modified', '');

$t->run();

###############################################################################

my $r;

# test for header field presence

$r = http_get('/t1');
like($r, qr/Cache-Control/, 'good expires');
like($r, qr/X-URI/, 'good add_header');
like($r, qr/X-Always/, 'good add_header always');

$r = http_get('/nx');
unlike($r, qr/Cache-Control/, 'bad expires');
unlike($r, qr/X-URI/, 'bad add_header');
like($r, qr/X-Always/, 'bad add_header always');

# various expires variants

like(http_get('/epoch'), qr/Expires:.*1970/, 'expires epoch');
like(http_get('/max'), qr/Expires:.*2037/, 'expires max');
unlike(http_get('/off'), qr/Expires:/, 'expires off');
like(http_get('/access'), qr/max-age=2048/, 'expires access');
like(http_get('/access_inner'), qr/max-age=2048/, 'expires inner');
like(http_get('/negative'), qr/no-cache/, 'expires negative');
like(http_get('/daily'), qr/Expires:.*:33 GMT/, 'expires daily');
like(http_get('/modified'), qr/max-age=204./, 'expires modified');

# expires with variables

like(http_get('/var?e=epoch'), qr/Expires:.*1970/, 'expires var epoch');
like(http_get('/var?e=max'), qr/Expires:.*2037/, 'expires var max');
unlike(http_get('/var?e=off'), qr/Expires:/, 'expires var off');
like(http_get('/var?e=2048'), qr/max-age=2048/, 'expires var access');
like(http_get('/var_inner?e=2048'), qr/max-age=2048/, 'expires var inner');
like(http_get('/var?e=-2048'), qr/no-cache/, 'expires var negative');
like(http_get('/var?e=@33s'), qr/Expires:.*:33 GMT/, 'expires var daily');
like(http_get('/var_modified?e=2048'), qr/max-age=204./,
	'expires var modified');

# some invalid cases

unlike(http_get('/var'), qr/Expires/, 'expires var empty');
unlike(http_get('/var?e=bad'), qr/Expires/, 'expires var bad');
unlike(http_get('/var_modified?e=epoch'), qr/Expires/,
	'expires var modified epoch');

###############################################################################
