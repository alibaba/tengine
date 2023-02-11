#!/usr/bin/perl

# Tests for server banners

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

my $t = Test::Nginx->new()->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        server_name  localhost;
        listen       127.0.0.1:8080;

        location /server_tokens_on {
            server_tokens on;
            return 404;
        }

        location /server_tokens_off {
            server_tokens off;
        }

        location /server_tag {
            server_tag Foobar;
        }

        location /server_tag_off {
            server_tag off;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_get('/server_tokens_on'), qr/Powered by Tengine\//, 'server tokens on');
like(http_get('/server_tokens_off'), qr/Powered by Tengine</,  'server tokens off');
like(http_get('/server_tag'), qr/Powered by Foobar/, 'server tag');
unlike(http_get('/server_tag_off'), qr/Powered.*<\/body>/, 'server tag off');

###############################################################################
