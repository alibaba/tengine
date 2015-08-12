#!/usr/bin/perl


###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use Socket qw/ CRLF /;

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(8);

##############################################################################
# Test 1 ( gzip_clear_etag off )
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    gzip on;
    gzip_http_version 1.0;
    gzip_clear_etag off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t {
            proxy_pass http://127.0.0.1:8080/;
        }
    }

}

EOF

$t->write_file('etag.html', 'test gzip clear etag');

$t->run();

###############################################################################

like(http('GET /t/etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . 'Accept-Encoding:gzip' . CRLF . CRLF), qr#ETag#, 'gzip_clear_etag off, proxy, gzip');
like(http('GET /t/etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . CRLF), qr#ETag#, 'gzip_clear_etag off, proxy, non-gzip');
like(http('GET /etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . 'Accept-Encoding:gzip' . CRLF . CRLF), qr#ETag#, 'gzip_clear_etag off, non-proxy, gzip');
like(http('GET /etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . CRLF), qr#ETag#, 'gzip_clear_etag off, non-proxy, non-gzip');

$t->stop();

##############################################################################
# Test 2 (gzip_clear_etag on (default))
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    gzip on;
    gzip_http_version 1.0;
   #gzip_clear_etag on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t {
            proxy_pass http://127.0.0.1:8080/;
        }
    }

}

EOF

$t->write_file('etag.html', 'test gzip clear etag');

$t->run();

###############################################################################

unlike(http('GET /t/etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . 'Accept-Encoding:gzip' . CRLF . CRLF), qr#ETag#, 'gzip_clear_etag on (default), proxy, gzip ');
like(http('GET /t/etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . CRLF), qr#ETag#, 'gzip_clear_etag on (default), proxy, non-gzip');
unlike(http('GET /etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . 'Accept-Encoding:gzip' . CRLF . CRLF), qr#ETag#, 'gzip_clear_etag on (default), non-proxy, gzip');
like(http('GET /etag.html HTTP/1.1' . CRLF . 'Host: localhost' . CRLF . 'Connection:close'. CRLF . CRLF), qr#ETag#, 'gzip_clear_etag on (default), non-proxy, non-gzip');

$t->stop();
