#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for location selection, an auto_redirect edge case.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(4)
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

        proxy_hide_header X-Location;
        add_header X-Location unset;

        # As of nginx 1.5.4, this results in the following
        # location tree:
        #
        #         "/a-b"
        # "/a-a"          "/a/"
        #
        # A request to "/a" is expected to match "/a/" with auto_redirect,
        # but with such a tree it tests locations "/a-b", "/a-a" and then
        # falls back to null location.
        #
        # Key factor is that "-" is less than "/".

        location /a/  { proxy_pass http://127.0.0.1:8080/a-a; }
        location /a-a { add_header X-Location a-a; return 204; }
        location /a-b { add_header X-Location a-b; return 204; }
    }
}

EOF

$t->run();

###############################################################################

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.5.6');

like(http_get('/a'), qr/301 Moved/, 'auto redirect');

}

like(http_get('/a/'), qr/X-Location: unset/, 'match a');
like(http_get('/a-a'), qr/X-Location: a-a/, 'match a-a');
like(http_get('/a-b'), qr/X-Location: a-b/, 'match a-b');

###############################################################################
