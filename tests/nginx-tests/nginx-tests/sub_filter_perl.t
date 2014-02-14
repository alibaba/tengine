#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for sub filter, extended tests using embedded perl.

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

my $t = Test::Nginx->new()->has(qw/http sub perl/)->plan(22)
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
        sub_filter foobarbaz replaced;

        location / {
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;
                $r->print("foo");
                $r->flush();
                $r->print("bar");
                $r->flush();
                $r->print("baz");
                return OK;
            }';
        }

        location /multi {
            sub_filter aab _replaced;
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;
                $r->print($r->variable("arg_a"));
                $r->print($r->variable("arg_b"));
                return OK;
            }';
        }

        location /short {
            sub_filter ab _replaced;
            perl 'sub {
                my $r = shift;
                $r->send_http_header("text/html");
                return OK if $r->header_only;
                $r->print($r->variable("arg_a"));
                $r->print($r->variable("arg_b"));
                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/flush'), qr/^replaced$/m, 'flush');

like(http_get('/multi?a=a&b=ab'), qr/^_replaced$/m, 'aab in a + ab');
like(http_get('/multi?a=a&b=aaab'), qr/^aa_replaced$/m, 'aab in a + aaab');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/multi?a=a&b=aab'), qr/^a_replaced$/m, 'aab in a + aab');
like(http_get('/multi?a=a&b=aaaab'), qr/^aaa_replaced$/m, 'aab in a + aaaab');

}

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/multi?a=aa&b=ab'), qr/^a_replaced$/m, 'aab in aa + ab');
like(http_get('/multi?a=aa&b=aab'), qr/^aa_replaced$/m, 'aab in aa + aab');
like(http_get('/multi?a=aa&b=aaab'), qr/^aaa_replaced$/m, 'aab in aa + aaab');

}

like(http_get('/multi?a=aa&b=aaaab'), qr/^aaaa_replaced$/m, 'aab in aa + aaaab');

# full backtracking

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/multi?a=aa&b=xaaab'), qr/^aaxa_replaced$/m, 'aab in aa + xaaab');
like(http_get('/multi?a=aa&b=axaaab'), qr/^aaaxa_replaced$/m,
	'aab in aa + axaaab');
like(http_get('/multi?a=aa&b=aaxaaab'), qr/^aaaaxa_replaced$/m,
	'aab in aa + aaxaaab');

}

# short pattern

like(http_get('/short?a=a&b=b'), qr/^_replaced$/m, 'ab in a + b');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/short?a=a&b=ab'), qr/^a_replaced$/m, 'ab in a + ab');

}

like(http_get('/short?a=a&b=aab'), qr/^aa_replaced$/m, 'ab in a + aab');
like(http_get('/short?a=a&b=aaab'), qr/^aaa_replaced$/m, 'ab in a + aaab');
like(http_get('/short?a=a&b=aaaab'), qr/^aaaa_replaced$/m, 'ab in a + aaaab');

like(http_get('/short?a=aa&b=b'), qr/^a_replaced$/m, 'ab in aa + b');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.3');

like(http_get('/short?a=aa&b=ab'), qr/^aa_replaced$/m, 'ab in aa + ab');

}

like(http_get('/short?a=aa&b=aab'), qr/^aaa_replaced$/m, 'ab in aa + aab');
like(http_get('/short?a=aa&b=aaab'), qr/^aaaa_replaced$/m, 'ab in aa + aaab');
like(http_get('/short?a=aa&b=aaaab'), qr/^aaaaa_replaced$/m, 'ab in aa + aaaab');

###############################################################################
