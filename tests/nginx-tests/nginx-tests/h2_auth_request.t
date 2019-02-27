#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with auth_request.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 rewrite proxy auth_request/)
	->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            return 200;
        }
        location /auth {
            add_header X-Body-File $request_body_file;
            client_body_buffer_size 512;
            auth_request /auth_request;
            proxy_pass http://127.0.0.1:8081/auth_proxy;
        }
        location /auth_request {
            proxy_pass http://127.0.0.1:8081/;
            proxy_pass_request_body off;
            proxy_set_header Content-Length "";
        }
        location /auth_proxy {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8081/;
        }
    }
}

EOF

$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

# second stream is used to induce body corruption issue

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/auth', method => 'POST', body => 'A' x 600 });
$s->new_stream({ path => '/auth', method => 'POST', body => 'B' x 600 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{'x-body'}, 'A' x 600, 'auth request body');
isnt($frame->{headers}->{'x-body-file'}, undef, 'auth request body file');

###############################################################################
