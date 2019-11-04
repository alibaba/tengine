#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for proxied subrequest with request body in file.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy ssi/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
        }

        location /proxy {
            proxy_pass http://127.0.0.1:8080/;
            client_body_in_file_only on;
            ssi on;
        }
    }
}

EOF

$t->write_file('ssi.html', 'X<!--# include virtual="test.html" -->X');
$t->write_file('test.html', 'YY');

$t->run();

###############################################################################

# Request body cache file is released once a response is got.
# If later a subrequest tries to use body, it fails.

like(http_get_body('/proxy/ssi.html', "1234567890"), qr/^XYYX$/m,
	'body in file in proxied subrequest');

###############################################################################

sub http_get_body {
	my ($url, $body, %extra) = @_;

	my $p = "GET $url HTTP/1.0" . CRLF
		. "Host: localhost" . CRLF
		. "Content-Length: " . (length $body) . CRLF . CRLF
		. $body;

	return http($p, %extra);
}

###############################################################################
