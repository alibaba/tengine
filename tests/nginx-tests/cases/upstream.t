#!/usr/bin/perl

# Tests for upstream module.

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

my $t = Test::Nginx->new()->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream foo {
        server 127.0.0.1:1970 id="localhost:1970";
        server 127.0.0.1:1971 id="localhost:1971";
    }

    upstream bar {
        server 127.0.0.1:1970 id="localhost:1970";
        server 127.0.0.1:1971 id="localhost:1971";
        ip_hash;
    }

    upstream baz {
        server 127.0.0.1:1970 id="localhost:1970";
        server 127.0.0.1:1971 id="localhost:1971";
        least_conn;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /foo {
            proxy_pass http://foo/index.html;
        }

        location /bar {
            proxy_pass http://bar/index.html;
        }

        location /baz {
            proxy_pass http://baz/index.html;
        }
    }

    server {
        listen       127.0.0.1:1970;
        server_name  localhost;

        location / {
            index index.html;
        }
    }

    server {
        listen       127.0.0.1:1971;
        server_name  localhost;

        location / {
            index index.html;
        }
    }
}

EOF

$t->write_file('index.html', 'hello, tengine!');

$t->run();

###############################################################################

like(http_get('/foo'), qr/hello, tengine!/, 'get index.html from foo servers');

like(http_get('/bar'), qr/hello, tengine!/, 'get index.html from bar servers');

like(http_get('/baz'), qr/hello, tengine!/, 'get index.html from baz servers');

###############################################################################
