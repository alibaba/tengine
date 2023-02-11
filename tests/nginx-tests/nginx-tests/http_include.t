#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for include directive.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy access/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        include ups.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        if ($arg_s) {
            include sif.conf;
        }

        location / {
            if ($arg_l) {
                include lif.conf;
            }
        }

        location /lmt {
            limit_except GET {
                include lmt.conf;
            }
        }

        location /proxy {
            add_header X-IP $upstream_addr always;
            proxy_pass http://u/backend;
        }

        location /backend { }
    }
}

EOF

my $p = port(8080);

$t->write_file('sif.conf', 'return 200 SIF;');
$t->write_file('lif.conf', 'return 200 LIF;');
$t->write_file('lmt.conf', 'deny all;');
$t->write_file('ups.conf', "server 127.0.0.1:$p;");

$t->run()->plan(5);

###############################################################################

like(http_get('/?s=1'), qr/SIF/, 'include in server if');
like(http_get('/?l=1'), qr/LIF/, 'include in location if');
like(http_post('/lmt'), qr/ 403 /, 'include in limit_except');
like(http_get('/proxy'), qr/X-IP: 127.0.0.1:$p/, 'include in upstream');

unlike(http_get('/'), qr/ 200 /, 'no include');

###############################################################################

sub http_post {
	my ($uri) = @_;
	http(<<EOF);
POST $uri HTTP/1.0
Host: localhost

EOF
}

###############################################################################
