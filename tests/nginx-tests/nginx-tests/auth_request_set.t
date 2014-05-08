#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for auth request module, auth_request_set.

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

my $t = Test::Nginx->new()->has(qw/http rewrite proxy auth_request/)
	->plan(6);

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

        location = /t1.html {
            auth_request /auth;
            auth_request_set $username $upstream_http_x_username;
            add_header X-Set-Username $username;
        }

        location = /t2.html {
            auth_request /auth;
            auth_request_set $username $upstream_http_x_username;
            error_page 404 = /fallback;
        }
        location = /fallback {
            add_header X-Set-Username $username;
            return 204;
        }

        location = /t3.html {
            auth_request /auth;
            auth_request_set $username $upstream_http_x_username;
            error_page 404 = @fallback;
        }
        location @fallback {
            add_header X-Set-Username $username;
            return 204;
        }

        location = /t4.html {
            auth_request /auth;
            auth_request_set $username $upstream_http_x_username;
            error_page 404 = /t4-fallback.html;
        }
        location = /t4-fallback.html {
            auth_request /auth2;
            auth_request_set $username $upstream_http_x_username;
            add_header X-Set-Username $username;
        }

        location = /t5.html {
            auth_request /auth;
            auth_request_set $args "setargs";
            proxy_pass http://127.0.0.1:8081/t5.html;
        }

        location = /t6.html {
            add_header X-Unset-Username "x${username}x";
            return 204;
        }

        location = /auth {
            proxy_pass http://127.0.0.1:8081;
        }
        location = /auth2 {
            proxy_pass http://127.0.0.1:8081;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location = /auth {
            add_header X-Username "username";
            return 204;
        }

        location = /auth2 {
            add_header X-Username "username2";
            return 204;
        }

        location = /t5.html {
            add_header X-Args $args;
            return 204;
        }
    }
}

EOF

$t->write_file('t1.html', '');
$t->write_file('t4-fallback.html', '');
$t->run();

###############################################################################

like(http_get('/t1.html'), qr/X-Set-Username: username/, 'set normal');
like(http_get('/t2.html'), qr/X-Set-Username: username/, 'set after redirect');
like(http_get('/t3.html'), qr/X-Set-Username: username/,
	'set after named location');
like(http_get('/t4.html'), qr/X-Set-Username: username2/,
	'set on second auth');

# there are two variables with set_handler: $args and $limit_rate
# we do test $args as it's a bit more simple thing to do

like(http_get('/t5.html'), qr/X-Args: setargs/, 'variable with set_handler');

# check that using variable without setting it returns empty content

like(http_get('/t6.html'), qr/X-Unset-Username: xx/, 'unset variable');

###############################################################################
