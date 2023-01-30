#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for msie_refresh.

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

my $t = Test::Nginx->new()->has(qw/http rewrite ssi/)->plan(5)
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

        msie_refresh on;

        location / {
            return 301 text;
        }

        location /space {
            return 301 "space ";
        }

        location /error_page {
            return 301;
            error_page 301 text;
        }

        location /off {
            msie_refresh off;
            return 301 text;
        }

        location /ssi {
            ssi on;
        }
    }
}

EOF

$t->write_file('ssi.html', 'X<!--#include virtual="/" -->X');
$t->run();

###############################################################################

like(get('/'), qr/Refresh.*URL=text"/, 'msie refresh');
like(get('/space'), qr/URL=space%20"/, 'msie refresh escaped url');
like(get('/error_page'), qr/URL=text"/, 'msie refresh error page');

unlike(get('/off'), qr/Refresh/, 'msie refresh disabled');

unlike(get('/ssi.html'), qr/^0\x0d\x0a?\x0d\x0a?\w/m, 'only final chunk');

###############################################################################

sub get {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
User-Agent: MSIE foo

EOF
}

###############################################################################
