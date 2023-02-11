#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for Expect: 100-continue support.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(5);

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
            proxy_pass http://127.0.0.1:8080/local;
        }
        location /local {
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_100_request('/', '1.1'), qr/ 100 /, 'expect 100 continue');

# Comparison of expectation values is case-insensitive for unquoted tokens.

like(http_100_request('/', '1.1', '100-Continue'), qr/ 100 /,
	'expect 100 continue case-insensitive');

# From RFC 2616, 8.2.3 Use of the 100 (Continue) Status:
#
#      - An origin server SHOULD NOT send a 100 (Continue) response if
#        the request message does not include an Expect request-header
#        field with the "100-continue" expectation, and MUST NOT send a
#        100 (Continue) response if such a request comes from an HTTP/1.0
#        (or earlier) client.

unlike(http_100_request('/', '1.0'), qr/ 100 /, 'no 100 continue via http 1.0');

# From RFC 2616, 14.20 Expect:
#
#    A server that does not understand or is unable to comply with any of
#    the expectation values in the Expect field of a request MUST respond
#    with appropriate error status. The server MUST respond with a 417
#    (Expectation Failed) status if any of the expectations cannot be met.
#
#    <..> If a server receives a request containing an
#    Expect field that includes an expectation-extension that it does not
#    support, it MUST respond with a 417 (Expectation Failed) status.

TODO: {
local $TODO = 'not yet';

like(http_100_request('/', '1.1', 'unknown'), qr/ 417 /, 'unknown expectation');
like(http_100_request('/', '1.1', 'token=param'), qr/ 417 /,
	'unsupported expectation extension');

}

###############################################################################

sub http_100_request {
	my ($url, $version, $value) = @_;
	$value = '100-continue' unless defined $value;
	http(<<EOF);
POST $url HTTP/$version
Host: localhost
Expect: $value
Content-Length: 0
Connection: close

EOF
}

###############################################################################
