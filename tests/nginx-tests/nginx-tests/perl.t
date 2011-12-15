#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for embedded perl module.

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

my $t = Test::Nginx->new()->has(qw/http perl rewrite/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            set $testvar "TEST";
            perl 'sub {
                use warnings;
                use strict;

                my $r = shift;

                $r->send_http_header("text/plain");

                return OK if $r->header_only;

                my $v = $r->variable("testvar");

                $r->print("$v");

                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/'), qr/TEST/, 'perl response');

###############################################################################
