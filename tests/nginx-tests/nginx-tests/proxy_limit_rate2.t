#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for the proxy_limit_rate directive, variables support.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_limit_rate $upstream_http_x_rate;
        proxy_buffer_size 4k;

        location / {
            proxy_pass http://127.0.0.1:8080/data;
            add_header  X-Msec $msec;
            add_trailer X-Msec $msec;
        }

        location /data {
            add_header  X-Rate $arg_e;
        }
    }
}

EOF

$t->write_file('data', 'X' x 40000);
$t->try_run('no proxy_limit_rate variables')->plan(4);

###############################################################################

my ($body, $t1, $t2) = get('/?e=20000');

cmp_ok($t2 - $t1, '>=', 1, 'proxy_limit_rate');
is($body, 'X' x 40000, 'response body');

# unlimited

($body, $t1, $t2) = get('/?e=0');

is($t2 - $t1, 0, 'proxy_limit_rate unlimited');
is($body, 'X' x 40000, 'response body unlimited');

###############################################################################

sub get {
	my ($uri) = @_;
	my $r = http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close

EOF

	http_content($r), $r =~ /X-Msec: (\d+)/g;
}

###############################################################################
