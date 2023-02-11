#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for the proxy_cookie_domain and proxy_cookie_path directives.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/);

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
            proxy_pass http://127.0.0.1:8081;

            proxy_cookie_domain www.example.org .example.com;
            proxy_cookie_domain .$server_name.com en.$server_name.org;
            proxy_cookie_domain ~^(.+)\.com$ $1.org;

            proxy_cookie_path /path/ /new/;
            proxy_cookie_path /$server_name/ /new/$server_name/;
            proxy_cookie_path ~^/regex/(.+)$ /$1;
            proxy_cookie_path ~*^/caseless/(.+)$ /$1;

            location /off/ {
                proxy_pass http://127.0.0.1:8081;

                proxy_cookie_domain off;
                proxy_cookie_path off;
            }
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            if ($arg_domain) {
                set $sc_domain "; Domain=$arg_domain";
            }
            if ($arg_path) {
                set $sc_path "; Path=$arg_path";
            }
            add_header Set-Cookie v=path=domain=$sc_domain$sc_path;
            return 200 OK;
        }
    }
}

EOF

$t->run()->plan(9);

###############################################################################

my $port = port(8080);

is(http_get_set_cookie('/?domain=www.Example.org'),
	'v=path=domain=; Domain=example.com', 'domain rewrite');
is(http_get_set_cookie('/?domain=.LocalHost.com'),
	'v=path=domain=; Domain=.en.localhost.org',
	'domain rewrite with vars');
is(http_get_set_cookie('/?domain=www.example.COM'),
	'v=path=domain=; Domain=www.example.org', 'domain regex rewrite');

is(http_get_set_cookie('/?path=/path/test.html'),
	'v=path=domain=; Path=/new/test.html', 'path rewrite');
is(http_get_set_cookie('/?path=/localhost/test.html'),
	'v=path=domain=; Path=/new/localhost/test.html',
	'path rewrite with vars');
is(http_get_set_cookie('/?path=/regex/test.html'),
	'v=path=domain=; Path=/test.html', 'path regex rewrite');
is(http_get_set_cookie('/?path=/CASEless/test.html'),
	'v=path=domain=; Path=/test.html', 'path caseless regex rewrite');

is(http_get_set_cookie('/?domain=www.example.org&path=/path/test.html'),
	'v=path=domain=; Domain=example.com; Path=/new/test.html',
	'domain and path rewrite');
is(http_get_set_cookie('/off/?domain=www.example.org&path=/path/test.html'),
	'v=path=domain=; Domain=www.example.org; Path=/path/test.html',
	'domain and path rewrite off');

###############################################################################

sub http_get_set_cookie {
	my ($uri) = @_;
	http_get("http://127.0.0.1:$port$uri") =~ /^Set-Cookie:\s(.+?)\x0d?$/mi;
	return $1;
}

###############################################################################
