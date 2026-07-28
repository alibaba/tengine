#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with preread request body.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy limit_req/)->plan(9);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone   $binary_remote_addr  zone=req:1m rate=20r/m;

    http2 on;

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2_body_preread_size 10;

        location /t { }
        location / {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8081/t;

            location /req {
                limit_req  zone=req burst=2;
                proxy_pass http://127.0.0.1:8081/t;
            }
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        http2_body_preread_size 0;

        location / {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8081/t;

            location /req {
                limit_req  zone=req burst=2;
                proxy_pass http://127.0.0.1:8081/t;
            }
        }
    }

    server {
        listen       127.0.0.1:8083;
        server_name  localhost;

        location / {
            add_header X-Body $request_body;
            proxy_pass http://127.0.0.1:8081/t;
        }
    }
}

EOF

$t->write_file('t', '');
$t->run();

###############################################################################

# request body within preread size (that is, stream window)

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ body => 'TEST' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body'}, 'TEST', 'within preread');

# request body beyond preread size
# RST_STREAM expected due stream window violation

TODO: {
local $TODO = 'not yet';

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body => 'TEST' x 10 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }], wait => 0.5);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 3, 'beyond preread - FLOW_CONTROL_ERROR');

}

# within preread size - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/req' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

$sid = $s->new_stream({ path => '/req', body => 'TEST' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body'}, 'TEST', 'within preread limited');

# processing request body without END_STREAM in preread

$sid = $s->new_stream({ path => '/req', body_more => 1, continuation => 1 });
$s->h2_continue($sid,
	{ headers => [{ name => 'content-length', value => '8' }]});

$s->h2_body('SEE', { body_more => 1 });
$s->read(all => [{ type => 'WINDOW_UPDATE' }]);

$s->h2_body('-THIS');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body'}, 'SEE-THIS', 'within preread limited - more');

# beyond preread size - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/req', body => 'TEST' x 10 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 3, 'beyond preread limited - FLOW_CONTROL_ERROR');


# zero preread size

TODO: {
local $TODO = 'not yet';

$s = Test::Nginx::HTTP2->new(port(8082));
$sid = $s->new_stream({ body => 'TEST' });
$frames = $s->read(all => [{ type => 'RST_STREAM' }], wait => 0.5);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 3, 'zero preread - FLOW_CONTROL_ERROR');

}

# zero preread size - limited

$s = Test::Nginx::HTTP2->new(port(8082));
$sid = $s->new_stream({ path => '/req', body => 'TEST' });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 3, 'zero preread limited - FLOW_CONTROL_ERROR');


# REFUSED_STREAM on request body prior SETTINGS acknowledgement

$s = Test::Nginx::HTTP2->new(port(8080), pure => 1);
$sid = $s->new_stream({ body => 'TEST' });
$frames = $s->read(all => [{ type => 'RST_STREAM' }]);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 7, 'no SETTINGS ack - REFUSED_STREAM');

# default preread size - no REFUSED_STREAM expected

$s = Test::Nginx::HTTP2->new(port(8083), pure => 1);
$sid = $s->new_stream({ body => 'TEST' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body'}, 'TEST', 'no SETTINGS ack - default preread');

###############################################################################
