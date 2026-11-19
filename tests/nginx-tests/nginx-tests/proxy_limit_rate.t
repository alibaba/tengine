#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for the proxy_limit_rate directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_keepalive/)->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8080;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_limit_rate 20000;
        proxy_buffer_size 4k;

        location / {
            proxy_pass http://127.0.0.1:8080/data;
            add_header  X-Msec $msec;
            add_trailer X-Msec $msec;
        }

        location /unlimited {
            proxy_pass http://127.0.0.1:8080/data;
            proxy_limit_rate 0;
            add_header  X-Msec $msec;
            add_trailer X-Msec $msec;
        }

        location /keepalive {
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_pass http://u/data;
        }

        location /data {
        }
    }
}

EOF

$t->write_file('data', 'X' x 40000);
$t->run();

###############################################################################

my ($body, $t1, $t2) = get('/');

cmp_ok($t2 - $t1, '>=', 1, 'proxy_limit_rate');
is($body, 'X' x 40000, 'response body');

# unlimited

($body, $t1, $t2) = get('/unlimited');

is($t2 - $t1, 0, 'proxy_limit_rate unlimited');
is($body, 'X' x 40000, 'response body unlimited');

# in case keepalive connection was saved with the delayed flag,
# the read timer used to be a delay timer in the next request

like(http_get('/keepalive'), qr/200 OK/, 'keepalive');
like(http_get('/keepalive'), qr/200 OK/, 'keepalive 2');

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
