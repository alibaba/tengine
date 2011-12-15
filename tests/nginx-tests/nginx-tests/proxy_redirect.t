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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(6);

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

            proxy_redirect http://127.0.0.1:8081/var_in_second/ /$some_var/;
            proxy_redirect http://127.0.0.1:8081/$some_var/ /replaced/;

            proxy_redirect ~^(.+)81/regex_w_([^/]+) $180/$2/test.html;
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
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            return http://127.0.0.1:8081$uri;
        }
    }
}

EOF

$t->run();

###############################################################################


is(http_get_location('http://127.0.0.1:8080/impl_default/test.html'),
	'http://127.0.0.1:8080/impl_default/test.html', 'implicit default');
is(http_get_location('http://127.0.0.1:8080/expl_default/test.html'),
	'http://127.0.0.1:8080/expl_default/test.html', 'explicit default');

is(http_get_location('http://127.0.0.1:8080/var_in_second/test.html'),
	'http://127.0.0.1:8080/var_here/test.html', 'variable in second arg');

TODO:{
local $TODO = 'support variables in first argument';

is(http_get_location('http://127.0.0.1:8080/var_here/test.html'),
	'http://127.0.0.1:8080/replaced/test.html', 'variable in first arg');

}

TODO:{
local $TODO = 'support for regular expressions';

is(http_get_location('http://127.0.0.1:8080/ReeegEX/test.html'),
	'http://127.0.0.1:8080/replaced/test.html', 'caseless regexp');
is(http_get_location('http://127.0.0.1:8080/regex_w_captures/test.html'),
	'http://127.0.0.1:8080/captures/test.html', 'regexp w/captures');

}


###############################################################################

sub http_get_location {
	my ($url) = @_;
	http_get($url) =~ /^Location:\s(.+?)\x0d?$/mi;
	return $1;
}
