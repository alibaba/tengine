#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for clearing of pre-existing Content-Range headers.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy cache/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache levels=1:2 keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:8080/stub;
            proxy_cache NAME;
            proxy_cache_valid 200 1m;
        }

        location /stub {
            add_header Content-Range stub;
            add_header Accept-Ranges bytes;
            return 200 "SEE-THIS";
        }
    }
}

EOF

$t->run()->plan(3);

###############################################################################

like(http_get_range('/', 'Range: bytes=0-4'),
	qr/ 206 (?!.*stub)/s, 'content range cleared - range request');
like(http_get_range('/', 'Range: bytes=0-2,4-'),
	qr/ 206 (?!.*stub)/s, 'content range cleared - multipart');
like(http_get_range('/', 'Range: bytes=1000-'),
	qr/ 416 (?!.*stub)/s, 'content range cleared - not satisfable');

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
