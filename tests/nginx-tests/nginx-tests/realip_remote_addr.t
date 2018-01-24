#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx realip module, realip_remote_addr variable.

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

my $t = Test::Nginx->new()->has(qw/http realip/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    set_real_ip_from  127.0.0.1/32;
    real_ip_header    X-Forwarded-For;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-IP $remote_addr;
            add_header X-Real-IP $realip_remote_addr;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('1', '');
$t->try_run('no realip_remote_addr');

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/') !~ /X-IP: 127.0.0.1/m;

$t->plan(4);

###############################################################################

like(http_get('/1'), qr/X-Real-IP: 127.0.0.1/m, 'request');
like(http_get('/'), qr/X-Real-IP: 127.0.0.1/m, 'request redirect');

like(http_xff('/1', '192.0.2.1'), qr/X-Real-IP: 127.0.0.1/m, 'realip');
like(http_xff('/', '192.0.2.1'), qr/X-Real-IP: 127.0.0.1/m, 'realip redirect');

###############################################################################

sub http_xff {
	my ($uri, $xff) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################
