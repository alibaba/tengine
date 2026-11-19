#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for predicate locations.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/);

plan(skip_all => 'not yet') unless $t->has_version('1.31.5');

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

        error_page   418 = @named;

        location $arg_a {
            add_header X-Location "a";
            return 204;
        }

        location = /exact {
            add_header X-Location "exact";
            return 204;
        }

        location /prefix {
            add_header X-Location "prefix";
            return 204;
        }

        location ^~ /noregex {
            add_header X-Location "noregex";
            return 204;

            location $arg_b {
                add_header X-Location "noregex b";
                return 204;
            }
        }

        location ~ ^/regex {
            add_header X-Location "regex";
            return 204;

            location $arg_b {
                add_header X-Location "regex b";
                return 204;
            }
        }

        location /nested {
            add_header X-Location "nested";
            return 204;

            location $arg_b {
                add_header X-Location "nested b";
                return 204;
            }
        }

        location = /named {
            return 418;
        }

        location @named {
            add_header X-Location "named";
            return 204;
        }

        location $arg_c {

            if ($arg_c = '2') {
                add_header X-Location "c if";
                return 204;
            }

            add_header X-Location "c";
            return 204;

            location = /c/exact {
                add_header X-Location "c exact";
                return 204;
            }

            location /c/prefix {
                add_header X-Location "c prefix";
                return 204;
            }

            location ~ ^/c/regex {
                add_header X-Location "c regex";
                return 204;
            }

            location $arg_d {
                add_header X-Location "c d";
                return 204;
            }
        }

        location /redirect {
            rewrite ^ /x?a=1? last;
        }
    }
}

EOF

$t->run()->plan(28);

###############################################################################

is(get('/x?a=1'), 'a', 'predicate');
is(get('/x'), '404', 'predicate not set');
is(get('/x?a='), '404', 'predicate empty');
is(get('/x?a=0'), '404', 'predicate zero');
is(get('/x?a=00'), 'a', 'predicate not zero');

is(get('/prefix'), 'prefix', 'prefix');
is(get('/prefix?a=1'), 'a', 'predicate over prefix');
is(get('/exact'), 'exact', 'exact');
is(get('/exact?a=1'), 'exact', 'exact over predicate');
is(get('/noregex'), 'noregex', 'noregex');
is(get('/noregex?a=1'), 'noregex', 'noregex over predicate');
is(get('/regex'), 'regex', 'regex');
is(get('/regex?a=1'), 'regex', 'regex over predicate');

is(get('/x?c=1'), 'c', 'predicate last');
is(get('/x?a=1&c=1'), 'a', 'first predicate wins');

is(get('/nested'), 'nested', 'nested');
is(get('/nested?b=1'), 'nested b', 'predicate in prefix location');
is(get('/nested?a=1&b=1'), 'nested b', 'nested predicate over predicate');
is(get('/noregex?b=1'), 'noregex b', 'predicate in noregex location');
is(get('/regex?b=1'), 'regex b', 'predicate in regex location');

is(get('/named?a=1'), 'named', 'named over predicate');

is(get('/c/exact?c=1&d=1'), 'c exact', 'exact in predicate location');
is(get('/c/prefix?c=1'), 'c prefix', 'prefix in predicate location');
is(get('/c/prefix?c=1&d=1'), 'c d', 'predicate over prefix in predicate');
is(get('/c/regex?c=1&d=1'), 'c regex', 'regex over predicate in predicate');
is(get('/x?c=1&d=1'), 'c d', 'predicate in predicate location');
is(get('/c/if?c=2'), 'c if', 'if in predicate location');

is(get('/redirect'), 'a', 'predicate after internal redirect');

###############################################################################

sub get {
	my ($uri) = @_;
	my $r = http_get($uri);
	return $1 if $r =~ /X-Location: (.+)\x0d/;
	return $1 if $r =~ /HTTP\/1\.\d (\d+)/;
}

###############################################################################
