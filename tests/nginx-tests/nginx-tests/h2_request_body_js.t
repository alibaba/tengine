#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 request body with njs subrequest in the body handler.

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

my $t = Test::Nginx->new()->has(qw/http http_v2/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    js_import test.js;

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        lingering_close off;

        location / {
            js_content test.sr_body;
            add_header X-Body $request_body;
        }

        location /sr { }
    }
}

EOF

$t->write_file('test.js', <<EOF);
function body_fwd_cb(r) {
    r.parent.return(r.status, r.responseText);
}

function sr_body(r) {
    r.subrequest('/sr', body_fwd_cb);
}

export default {sr_body};

EOF

$t->write_file('sr', 'SEE-THIS');
$t->try_run('no njs available')->plan(3);

###############################################################################

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ body => 'TEST' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'status');
is($frame->{headers}->{'x-body'}, 'TEST', 'request body');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'SEE-THIS', 'response body');

###############################################################################
