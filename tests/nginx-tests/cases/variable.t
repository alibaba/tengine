#!/usr/bin/perl

# Tests for variable

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

my $t = Test::Nginx->new()->plan(12);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /base64_decode {
            #output: test
            set $t "dGVzdA==";
            rewrite .* http://127.0.0.1/$base64_decode_t;
        }

        location /md5_encode {
            #output: 4621d373cade4e83
            set $t "test";
            rewrite .* http://127.0.0.1/$md5_encode_t;
        }

        location /escape_uri {
            #output: te%20st
            set $t "te st";
            rewrite .* http://127.0.0.1/$escape_uri_t;
        }

        location /full_request {
            #output: te%20st
            rewrite .* http://127.0.0.1/$full_request;
        }

        location /full_request_escape {
            #output: te%20st
            rewrite .* http://127.0.0.1/$escape_uri_full_request?;
        }

        location /normalized_request {
            return http://127.0.0.1/${normalized_request}-;
        }

    }
}

EOF

$t->run();

###############################################################################

like(http_get('/base64_decode'), qr/test/, 'base64_decode');
like(http_get('/md5_encode'), qr/4621d373cade4e83/, 'md5_encode');
like(http_get('/escape_uri'), qr/te%20st/, 'escape_uri');
like(http_get('/full_request'), qr#http://localhost:8080/full_request#, 'full_reqeust');
like(http_get('/full_request_escape/<>'), qr#http://localhost:8080/full_request_escape/<>#, 'full_reqeust_escape');
like(http_get('/full_request_escape/??'), qr#http://localhost:8080/full_request_escape/\?%3F#, 'full_reqeust_escape');
like(http_get('/normalized_request'), qr#http://localhost:8080/normalized_request-#, 'normalized_request');
like(http_get('/normalized_request/?t=%ab#h1'), qr#http://localhost:8080/normalized_request/\?t=%AB-#, 'normalized_request');
like(http_get('/normalized_request/?t=%%ab#h1'), qr#http://localhost:8080/normalized_request/\?t=%%AB-#, 'normalized_request');
like(http_get('/normalized_request/?t=%%%ab#h1'), qr#http://localhost:8080/normalized_request/\?t=%%%AB-#, 'normalized_request');
like(http_get('/normalized_request/?t=%a%fF#h1'), qr#http://localhost:8080/normalized_request/\?t=%a%FF-#, 'normalized_request');
like(http_get('/normalized_request/?t=%a%fG#h1'), qr#http://localhost:8080/normalized_request/\?t=%a%fG-#, 'normalized_request');

###############################################################################
