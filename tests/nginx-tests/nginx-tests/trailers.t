#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for trailers in headers filter module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(17)
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

        add_trailer  X-Var $host;
        add_trailer  X-Always $host always;
        add_trailer  X-Empty '';
        add_trailer  X-Sent-HTTP $sent_http_accept_ranges;
        add_trailer  X-Sent-Trailer $sent_trailer_x_var;
        add_trailer  X-Complex $host:$host;

        location /t1 {
        }

        location /nx {
        }

        location /header {
            add_header X-Var foo;
        }

        location /empty {
            add_trailer X-Var $host;
        }

        location /not_chunked {
            chunked_transfer_encoding off;
        }

        location /proxy {
            proxy_pass http://127.0.0.1:8080/t1;
            add_trailer X-Length $upstream_response_length;
        }
    }
}

EOF

$t->write_file('t1', 'SEE-THIS');
$t->write_file('header', '');
$t->run();

###############################################################################

my $r;

$r = get('/t1');
like($r, qr/8${CRLF}SEE-THIS${CRLF}0${CRLF}(.+${CRLF}){5}$CRLF/, 'trailers');
unlike($r, qr/X-Var.*SEE-THIS/s, 'not in headers');
like($r, qr/X-Var: localhost/, 'add_trailer');
like($r, qr/X-Always/, 'add_trailer always');
like($r, qr/X-Sent-HTTP: bytes/, 'add_trailer sent_http');
like($r, qr/X-Sent-Trailer: localhost/, 'add_trailer sent_trailer');
like($r, qr/X-Complex: localhost:localhost/, 'add_trailer complex');
unlike($r, qr/X-Empty/, 'add_trailer empty');

$r = get('/nx');
unlike($r, qr/X-Var/, 'add_trailer bad');
like($r, qr/X-Always/, 'add_trailer bad always');

like(get('/header'), qr/foo.*^0$CRLF.*X-Var: localhost/ms, 'header name');

like(http_get('/t1'), qr/${CRLF}SEE-THIS$/, 'no trailers - http10');
unlike(get('/not_chunked'), qr/X-Always/, 'no trailers - not chunked');
unlike(head('/t1'), qr/X-Always/, 'no trailers - head');

unlike(get('/empty'), qr/X-Var/, 'no trailers expected');

$r = get('/proxy');
like($r, qr/SEE-THIS.*X-Length: 8/ms, 'upstream response variable');
unlike($r, qr/X-Var/, 'inheritance');

###############################################################################

sub get {
	my ($uri) = @_;
	http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

sub head {
	my ($uri) = @_;
	http(<<EOF);
HEAD $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

###############################################################################
