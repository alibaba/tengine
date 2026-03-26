#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module, proxy_next_upstream directive with sticky
# upstreams.  Used to check that all bad backends are tried once.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_sticky/)
	->has(qw/upstream_ip_hash upstream_least_conn/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_backend_2 {
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    upstream u_iph_sticky {
        ip_hash;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    upstream u_lc_sticky {
        least_conn;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /backend_2 {
            proxy_pass http://u_backend_2;
        }

        location /rr_sticky {
            proxy_pass http://u_rr_sticky;
            proxy_next_upstream http_404;
            error_page 404 /404;
            proxy_intercept_errors on;
        }

        location /iph_sticky {
            proxy_pass http://u_iph_sticky;
            proxy_next_upstream http_404;
            error_page 404 /404;
            proxy_intercept_errors on;
        }

        location /lc_sticky {
            proxy_pass http://u_lc_sticky;
            proxy_next_upstream http_404;
            error_page 404 /404;
            proxy_intercept_errors on;
        }

        location /404 {
            return 200 "$upstream_addr\n";
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        location / {
            return 404;
        }
    }
}

EOF

$t->try_run('no sticky upstream')->plan(3);

###############################################################################

my ($port1, $port2) = (port(8081), port(8082));

my ($cookie) = http_get('/backend_2') =~ /Set-Cookie: sticky=(\w+)/;

like(sticky_request('/rr_sticky', "sticky=$cookie"),
	qr/^127.0.0.1:($port1, 127.0.0.1:$port2|$port2, 127.0.0.1:$port1)$/mi,
	'round robin sticky');

like(sticky_request('/lc_sticky', "sticky=$cookie"),
	qr/^127.0.0.1:($port1, 127.0.0.1:$port2|$port2, 127.0.0.1:$port1)$/mi,
	'least_conn sticky');

# NB: depends on ip_hash product based on remote address fixed to "127.0.0.1"

like(sticky_request('/iph_sticky', "sticky=$cookie"),
	qr/^127.0.0.1:($port1, 127.0.0.1:$port2|$port2, 127.0.0.1:$port1)$/mi,
	'ip_hash sticky');

###############################################################################

sub sticky_request {
	my ($uri, $cookie) = @_;

	my $request = <<EOF;
GET $uri HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF

	return http($request);
}
