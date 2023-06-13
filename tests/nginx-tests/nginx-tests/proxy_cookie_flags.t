#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for the proxy_cookie_flags directive.

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

            proxy_cookie_flags a secure httponly samesite=none;
            proxy_cookie_flags b secure httponly samesite=lax;
            proxy_cookie_flags c secure httponly samesite=strict;
            proxy_cookie_flags d nosecure nohttponly nosamesite;

            proxy_cookie_flags $arg_complex secure;
            proxy_cookie_flags ~BAR httponly;

            location /off/ {
                proxy_pass http://127.0.0.1:8081;
                proxy_cookie_flags off;
            }
        }

        location /var/ {
            proxy_pass http://127.0.0.1:8081;
            proxy_cookie_flags $arg_v $arg_f1 $arg_f2 $arg_f3;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            set $c "$arg_v$arg_complex=path=domain=; Domain=example.org$arg_f";
            add_header Set-Cookie $c;
            return 200 OK;
        }
    }
}

EOF

$t->run()->plan(14);

###############################################################################

is(http_get_set_cookie('/?v=a'),
	'a=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=None',
	'flags set all');
is(http_get_set_cookie('/?v=b'),
	'b=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=Lax',
	'flags set lax');
is(http_get_set_cookie('/?v=c'),
	'c=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=Strict',
	'flags set strict');

# edit already set flags

is(http_get_set_cookie('/?v=a&f=;Secure;HttpOnly;SameSite=Lax'),
	'a=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=None',
	'flags reset all');
is(http_get_set_cookie('/?v=b&f=;Secure;HttpOnly;SameSite=None'),
	'b=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=Lax',
	'flags reset lax');
is(http_get_set_cookie('/?v=c&f=;Secure;HttpOnly;SameSite=None'),
	'c=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=Strict',
	'flags reset strict');

is(http_get_set_cookie('/?v=d&f=;secure;httponly;samesite=lax'),
	'd=path=domain=; Domain=example.org',
	'flags remove');

is(http_get_set_cookie('/?v=nx&f=;samesite=none'),
	'nx=path=domain=; Domain=example.org;samesite=none', 'flags no match');

is(http_get_set_cookie('/?complex=v'),
	'v=path=domain=; Domain=example.org; Secure', 'flags variable');
is(http_get_set_cookie('/?v=foobarbaz'),
	'foobarbaz=path=domain=; Domain=example.org; HttpOnly', 'flags regex');

is(http_get_set_cookie('/off/?v=a'), 'a=path=domain=; Domain=example.org',
	'flags off');

# variables in flags

is(http_get_set_cookie('/var/?v=v&f1=secure&f2=httponly&f3=samesite=none'),
	'v=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=None',
	'flags set');
is(http_get_set_cookie('/var/?v=v&f=;Secure;HttpOnly;SameSite=Lax' .
	'&f1=secure&f2=httponly&f3=samesite=none'),
	'v=path=domain=; Domain=example.org; Secure; HttpOnly; SameSite=None',
	'flags reset');
is(http_get_set_cookie('/var/?v=v&f=;secure;httponly;samesite=lax' .
	'&f1=nosecure&f2=nohttponly&f3=nosamesite'),
	'v=path=domain=; Domain=example.org',
	'flags remove');

###############################################################################

sub http_get_set_cookie {
	my ($uri) = @_;
	http_get($uri) =~ /^Set-Cookie:\s(.+?)\x0d?$/mi;
	return $1;
}

###############################################################################
