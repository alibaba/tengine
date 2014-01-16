#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for auth request module with satisfy directive.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http rewrite access auth_basic auth_request/)
	->plan(18);

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

        location / {
            return 444;
        }

        location /all/allow {
            satisfy all;
            allow all;
            auth_request /auth;
        }

        location /all/deny {
            satisfy all;
            deny all;
            auth_request /auth;
        }

        location /all/basic {
            satisfy all;
            auth_basic "restricted";
            auth_basic_user_file %%TESTDIR%%/htpasswd;
            auth_request /auth;
        }

        location /any/allow {
            satisfy any;
            allow all;
            auth_request /auth;
        }

        location /any/deny {
            satisfy any;
            deny all;
            auth_request /auth;
        }

        location /any/basic {
            satisfy any;
            auth_basic "restricted";
            auth_basic_user_file %%TESTDIR%%/htpasswd;
            auth_request /auth;
        }

        location = /auth {
            if ($request_uri ~ "open$") {
                return 204;
            }
            if ($request_uri ~ "unauthorized$") {
                return 401;
            }
            if ($request_uri ~ "forbidden$") {
                return 403;
            }
        }
    }
}

EOF

$t->write_file('htpasswd', 'user:{PLAIN}secret' . "\n");
$t->run();

###############################################################################

# satisfy all - first 401/403 wins

like(http_get('/all/allow+open'), qr/ 404 /, 'all allow+open');
like(http_get('/all/allow+unauthorized'), qr/ 401 /, 'all allow+unauthorized');
like(http_get('/all/allow+forbidden'), qr/ 403 /, 'all allow+forbidden');

like(http_get('/all/deny+open'), qr/ 403 /, 'all deny+open');
like(http_get('/all/deny+unauthorized'), qr/ 403 /, 'all deny+unauthorized');
like(http_get('/all/deny+forbidden'), qr/ 403 /, 'all deny+forbidden');

like(http_get('/all/basic+open'), qr/ 401 /, 'all basic+open');
like(http_get('/all/basic+unauthorized'), qr/ 401 /, 'all basic+unauthorized');
like(http_get('/all/basic+forbidden'), qr/ 401 /, 'all basic+forbidden');

# satisfy any - first ok wins
# additionally, 403 shouldn't override 401 status

like(http_get('/any/allow+open'), qr/ 404 /, 'any allow+open');
like(http_get('/any/allow+unauthorized'), qr/ 404 /, 'any allow+unauthorized');
like(http_get('/any/allow+forbidden'), qr/ 404 /, 'any allow+forbidden');

like(http_get('/any/deny+open'), qr/ 404 /, 'any deny+open');
like(http_get('/any/deny+unauthorized'), qr/ 401 /, 'any deny+unauthorized');
like(http_get('/any/deny+forbidden'), qr/ 403 /, 'any deny+forbidden');

like(http_get('/any/basic+open'), qr/ 404 /, 'any basic+open');
like(http_get('/any/basic+unauthorized'), qr/ 401 /, 'any basic+unauthorized');

TODO: {
local $TODO = 'not yet, ticket 285' unless $t->has_version('1.5.7');

like(http_get('/any/basic+forbidden'), qr/ 401 /, 'any basic+forbidden');

}

###############################################################################
