#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for embedded perl module, $r->sleep().

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

my $t = Test::Nginx->new()->has(qw/http perl ssi/)->plan(2)
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

        location / {
            ssi on;
            sendfile_max_chunk 100;
            postpone_output 0;
        }

        location /sleep {
            perl 'sub {
                my $r = shift;

                $r->sleep(100, sub {
                    my $r = shift;
                    $r->send_http_header;
                    $r->print("it works");
                    return OK;
                });

                return OK;
            }';
        }
    }
}

EOF

$t->write_file('subrequest.html', ('x' x 200) .
	'X<!--#include virtual="/sleep" -->X');

$t->run();

###############################################################################

like(http_get('/sleep'), qr/works/, 'perl sleep');
like(http_get('/subrequest.html'), qr/works/, 'perl sleep in subrequest');

###############################################################################
