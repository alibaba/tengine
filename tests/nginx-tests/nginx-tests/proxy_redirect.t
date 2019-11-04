#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for the proxy_redirect directive.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(15);

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
            set $some_var var_here;

            proxy_pass http://127.0.0.1:8081;

            proxy_redirect http://127.0.0.1:8081/var_in_second/
                           /$some_var/;
            proxy_redirect http://127.0.0.1:8081/$some_var/ /replaced/;

            proxy_redirect ~^(.+)/regex_w_([^/]+) $1/$2/test.html;
            proxy_redirect ~*re+gexp? /replaced/test.html;
        }

        location /expl_default/ {
            proxy_pass http://127.0.0.1:8081/replace_this/;
            proxy_redirect wrong wrong;
            proxy_redirect default;
        }

        location /impl_default/ {
            proxy_pass http://127.0.0.1:8081/replace_this/;
        }

        location /off/ {
            proxy_pass http://127.0.0.1:8081/;
            proxy_redirect off;

            location /off/on/ {
                proxy_pass http://127.0.0.1:8081;
                proxy_redirect http://127.0.0.1:8081/off/ /;

                location /off/on/on/ {
                    proxy_pass http://127.0.0.1:8081;
                }
            }
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header Refresh "7; url=http://127.0.0.1:8081$uri";
            return http://127.0.0.1:8081$uri;
        }
    }
}

EOF

$t->run();

###############################################################################

my ($p0, $p1) = (port(8080), port(8081));

is(http_get_location("http://127.0.0.1:$p0/impl_default/test.html"),
	"http://127.0.0.1:$p0/impl_default/test.html", 'implicit default');
is(http_get_location("http://127.0.0.1:$p0/expl_default/test.html"),
	"http://127.0.0.1:$p0/expl_default/test.html", 'explicit default');

is(http_get_refresh("http://127.0.0.1:$p0/impl_default/test.html"),
	'7; url=/impl_default/test.html', 'implicit default (refresh)');
is(http_get_refresh("http://127.0.0.1:$p0/expl_default/test.html"),
	'7; url=/expl_default/test.html', 'explicit default (refresh)');

is(http_get_location("http://127.0.0.1:$p0/var_in_second/test.html"),
	"http://127.0.0.1:$p0/var_here/test.html", 'variable in second arg');
is(http_get_refresh("http://127.0.0.1:$p0/var_in_second/test.html"),
	'7; url=/var_here/test.html', 'variable in second arg (refresh)');

is(http_get_location("http://127.0.0.1:$p0/off/test.html"),
	"http://127.0.0.1:$p1/test.html", 'rewrite off');
is(http_get_location("http://127.0.0.1:$p0/off/on/test.html"),
	"http://127.0.0.1:$p0/on/test.html", 'rewrite off overwrite');

is(http_get_location("http://127.0.0.1:$p0/off/on/on/test.html"),
	"http://127.0.0.1:$p0/on/on/test.html", 'rewrite inheritance');

is(http_get_location("http://127.0.0.1:$p0/var_here/test.html"),
	"http://127.0.0.1:$p0/replaced/test.html", 'variable in first arg');
is(http_get_refresh("http://127.0.0.1:$p0/var_here/test.html"),
	'7; url=/replaced/test.html', 'variable in first arg (refresh)');

is(http_get_location("http://127.0.0.1:$p0/ReeegEX/test.html"),
	"http://127.0.0.1:$p0/replaced/test.html", 'caseless regexp');
is(http_get_location("http://127.0.0.1:$p0/regex_w_captures/test.html"),
	"http://127.0.0.1:$p1/captures/test.html", 'regexp w/captures');

is(http_get_refresh("http://127.0.0.1:$p0/ReeegEX/test.html"),
	'7; url=/replaced/test.html', 'caseless regexp (refresh)');
is(http_get_refresh("http://127.0.0.1:$p0/regex_w_captures/test.html"),
	"7; url=http://127.0.0.1:$p1/captures/test.html",
	'regexp w/captures (refresh)');

###############################################################################

sub http_get_location {
	my ($url) = @_;
	http_get($url) =~ /^Location:\s(.+?)\x0d?$/mi;
	return $1;
}

sub http_get_refresh {
	my ($url) = @_;
	http_get($url) =~ /^Refresh:\s(.+?)\x0d?$/mi;
	return $1;
}
