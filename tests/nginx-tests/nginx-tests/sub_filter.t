#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for sub filter.

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

my $t = Test::Nginx->new()->has(qw/http rewrite sub/)->plan(14)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        sub_filter_types *;
        sub_filter foo bar;

        location / {
        }

        location /once {
            return 200 $arg_b;
        }

        location /many {
            sub_filter_once off;
            return 200 $arg_b;
        }

        location /complex {
            sub_filter abac _replaced;
            return 200 $arg_b;
        }

        location /complex2 {
            sub_filter ababX _replaced;
            return 200 $arg_b;
        }

        location /complex3 {
            sub_filter aab _replaced;
            return 200 $arg_b;
        }
    }
}

EOF

$t->write_file('foo.html', 'foo');
$t->write_file('foofoo.html', 'foofoo');
$t->run();

###############################################################################

like(http_get('/foo.html'), qr/bar/, 'sub_filter');
like(http_get('/foofoo.html'), qr/barfoo/, 'once default');

like(http_get('/once?b=foofoo'), qr/barfoo/, 'once');
like(http_get('/many?b=foofoo'), qr/barbar/, 'many');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/many?b=fo'), qr/fo/, 'incomplete');
like(http_get('/many?b=foofo'), qr/barfo/, 'incomplete long');

}

like(http_get('/complex?b=abac'), qr/_replaced/, 'complex');
like(http_get('/complex?b=abaabac'), qr/aba_replaced/, 'complex 1st char');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/complex?b=ababac'), qr/replaced/, 'complex 2nd char');

}

like(http_get('/complex2?b=ababX'), qr/_replaced/, 'complex2');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/complex2?b=abababX'), qr/ab_replaced/, 'complex2 long');

}

like(http_get('/complex3?b=aab'), qr/_replaced/, 'complex3 aab in aab');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/complex3?b=aaab'), qr/a_replaced/, 'complex3 aab in aaab');

}

like(http_get('/complex3?b=aaaab'), qr/aa_replaced/, 'complex3 aab in aaaab');

###############################################################################
