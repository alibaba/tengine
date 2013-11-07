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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(2);

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

like(http_100_request('/', '1.1'), qr/100/, 'expect 100 continue');

# From RFC 2616, 8.2.3 Use of the 100 (Continue) Status:
#
#      - An origin server SHOULD NOT send a 100 (Continue) response if
#        the request message does not include an Expect request-header
#        field with the "100-continue" expectation, and MUST NOT send a
#        100 (Continue) response if such a request comes from an HTTP/1.0
#        (or earlier) client.

unlike(http_100_request('/', '1.0'), qr/100/, 'no 100 continue via http 1.0');

###############################################################################

sub http_100_request {
	my ($url, $version) = @_;
	my $r = http(<<EOF);
POST $url HTTP/$version
Host: localhost
Expect: 100-continue
Content-Length: 0
Connection: close

EOF
}

###############################################################################
