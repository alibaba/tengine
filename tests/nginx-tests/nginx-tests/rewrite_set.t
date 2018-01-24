#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for rewrite set.

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

my $t = Test::Nginx->new()->has(qw/http rewrite ssi/)->plan(4);

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

        ssi on;

        location /t1 {
            set $http_foo "set_foo";
            return 200 'X<!--#echo var="http_foo" -->X';
        }

        location /t2 {
            return 200 'X<!--#echo var="http_bar" -->X';
        }

        location /t3 {
            return 200 'X<!--#echo var="http_baz" -->X';
        }

        location /t4 {
            set $http_connection "bar";
            return 200 "X${http_connection}X\n";
        }

        # set in other context
        location /other {
            set $http_bar "set_bar";
        }
    }
}

EOF

$t->run();

###############################################################################

# prefixed variables

like(http_get_extra('/t1.html', 'Foo: http_foo'), qr/Xset_fooX/,
	'set in this context');
like(http_get_extra('/t2.html', 'Bar: http_bar'), qr/Xhttp_barX/,
	'set in other context');

like(http_get_extra('/t3.html', 'Baz: http_baz'), qr/Xhttp_bazX/, 'not set');

like(http_get('/t4.html'), qr/XbarX/, 'set get in return');

###############################################################################

sub http_get_extra {
	my ($uri, $extra) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
$extra

EOF
}

###############################################################################
