#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for proxy_next_upstream non_idempotent.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_keepalive/)
	->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8081 max_fails=0;
    }

    upstream uk {
        server 127.0.0.1:8081 max_fails=0;
        server 127.0.0.1:8081 max_fails=0;
        keepalive 10;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-IP $upstream_addr always;

        location / {
            proxy_pass http://u;
            proxy_next_upstream error timeout http_404;
        }

        location /non {
            proxy_pass http://u;
            proxy_next_upstream error timeout non_idempotent;
        }

        location /keepalive {
            proxy_pass http://uk;
            proxy_next_upstream error timeout;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        keepalive_requests 1;

        location / {
            return 444;
        }

        location /404 {
            return 404 SEE-THIS;
        }

        location /keepalive/establish {
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

# non-idempotent requests should not be retried by default
# if a request has been sent to a backend

like(http_get('/'), qr/X-IP: (\S+), \1\x0d?$/m, 'get');
like(http_post('/'), qr/X-IP: (\S+)\x0d?$/m, 'post');

# non-idempotent requests should not be retried by default,
# in particular, not emit builtin error page due to next upstream

like(http_get('/404'), qr/X-IP: (\S+), \1.*SEE-THIS/s, 'get 404');
like(http_post('/404'), qr/X-IP: (\S++)(?! ).*SEE-THIS/s, 'post 404');

# with "proxy_next_upstream non_idempotent" there is no
# difference between idempotent and non-idempotent requests,
# non-idempotent requests are retried as usual

like(http_get('/non'), qr/X-IP: (\S+), \1\x0d?$/m, 'get non_idempotent');
like(http_post('/non'), qr/X-IP: (\S+), \1\x0d?$/m, 'post non_idempotent');

# cached connections follow the same rules

like(http_get('/keepalive/establish'), qr/204 No Content/m, 'keepalive');
like(http_post('/keepalive/drop'), qr/X-IP: (\S+)\x0d?$/m, 'keepalive post');

###############################################################################

sub http_post {
	my ($uri, %extra) = @_;
	my $cl = $extra{cl} || 0;

	http(<<"EOF");
POST $uri HTTP/1.0
Content-Length: $cl

EOF
}

###############################################################################
