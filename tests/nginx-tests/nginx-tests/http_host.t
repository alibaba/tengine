#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev

# Tests for host parsing in requests.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(37);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen  127.0.0.1:8080;
        server_name  localhost;

        location / {
            return  200  $host;
        }
    }
}

EOF

$t->run();

###############################################################################

is(http_host_header('www.abcd-ef.g02.xyz'), 'www.abcd-ef.g02.xyz',
	'domain w/o port (host header)');
is(http_host_header('abcd-ef.g02.xyz:' . port(8080)), 'abcd-ef.g02.xyz',
	'domain w/port (host header)');

is(http_absolute_path('abcd-ef.g02.xyz'), 'abcd-ef.g02.xyz',
	'domain w/o port (absolute request)');
is(http_absolute_path('www.abcd-ef.g02.xyz:10'), 'www.abcd-ef.g02.xyz',
	'domain w/port (absolute request)');


is(http_host_header('www.abcd-ef.g02.xyz.'), 'www.abcd-ef.g02.xyz',
	'domain w/ ending dot w/o port (host header)');

is(http_host_header('abcd-ef.g02.xyz.:88'), 'abcd-ef.g02.xyz',
	'domain w/ ending dot w/port (host header)');

is(http_absolute_path('www.abcd-ef.g02.xyz.'), 'www.abcd-ef.g02.xyz',
	'domain w/ ending dot w/o port (absolute request)');
is(http_absolute_path('abcd-ef.g02.xyz.:2'), 'abcd-ef.g02.xyz',
	'domain w/ ending dot w/port (absolute request)');


is(http_absolute_path('AbC-d93.0.34ZhGt-s.nk.Ru'), 'abc-d93.0.34zhgt-s.nk.ru',
	'mixed case domain w/o port (absolute request)');
is(http_host_header('AbC-d93.0.34ZhGt-s.nk.Ru:88'), 'abc-d93.0.34zhgt-s.nk.ru',
	'mixed case domain w/port (host header)');


is(http_host_header('123.40.56.78'), '123.40.56.78',
	'ipv4 w/o port (host header)');
is(http_host_header('123.49.0.78:987'), '123.49.0.78',
	'ipv4 w/port (host header)');

is(http_absolute_path('123.49.0.78'), '123.49.0.78',
	'ipv4 w/o port (absolute request)');
is(http_absolute_path('123.40.56.78:123'), '123.40.56.78',
	'ipv4 w/port (absolute request)');

is(http_host_header('[abcd::ef98:0:7654:321]'), '[abcd::ef98:0:7654:321]',
	'ipv6 literal w/o port (host header)');
is(http_host_header('[abcd::ef98:0:7654:321]:80'), '[abcd::ef98:0:7654:321]',
	'ipv6 literal w/port (host header)');

is(http_absolute_path('[abcd::ef98:0:7654:321]'), '[abcd::ef98:0:7654:321]',
	'ipv6 literal w/o port (absolute request)');
is(http_absolute_path('[abcd::ef98:0:7654:321]:5'), '[abcd::ef98:0:7654:321]',
	'ipv6 literal w/port (absolute request)');

is(http_host_header('[::ffff:12.30.67.89]'), '[::ffff:12.30.67.89]',
	'ipv4-mapped ipv6 w/o port (host header)');
is(http_host_header('[::123.45.67.89]:4321'), '[::123.45.67.89]',
	'ipv4-mapped ipv6 w/port (host header)');

is(http_absolute_path('[::123.45.67.89]'), '[::123.45.67.89]',
	'ipv4-mapped ipv6 w/o port (absolute request)');
is(http_absolute_path('[::ffff:12.30.67.89]:4321'), '[::ffff:12.30.67.89]',
	'ipv4-mapped ipv6 w/port (absolute request)');

like(http_host_header('example.com/\:552', 1), qr/ 400 /,
	'domain w/ path separators (host header)');
like(http_absolute_path('\e/xample.com', 1), qr/ 400 /,
	'domain w/ path separators (absolute request)');

like(http_host_header('..examp-LE.com', 1), qr/ 400 /,
	'domain w/ double dot (host header)');
like(http_absolute_path('com.exa-m.45..:', 1), qr/ 400 /,
	'domain w/ double dot (absolute request)');


like(http_host_header('[abcd::e\f98:0/:7654:321]', 1), qr/ 400 /,
	'ipv6 literal w/ path separators (host header)');
like(http_absolute_path('[abcd\::ef98:0:7654:321/]:12', 1), qr/ 400 /,
	'ipv6 literal w/ path separators (absolute request)');

like(http_host_header('[abcd::ef98:0:7654:321]..:98', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (host header)');
like(http_absolute_path('[ab..cd::ef98:0:7654:321]', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (absolute request)');


like(http_host_header('[abcd::ef98:0:7654:321]..:98', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (host header)');
like(http_absolute_path('[ab..cd::ef98:0:7654:321]', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (absolute request)');


# As per RFC 3986,
# http://tools.ietf.org/html/rfc3986#section-3.2.2
#
# IP-literal    = "[" ( IPv6address / IPvFuture  ) "]"
#
# IPvFuture     = "v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )
#
# sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
#               / "*" / "+" / "," / ";" / "="
#
# unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
#

is(http_host_header(
	'[v0123456789aBcDeF.!$&\'()*+,;=-._~AbCdEfGhIjKlMnOpQrStUvWxYz'
	. '0123456789:]'),
	'[v0123456789abcdef.!$&\'()*+,;=-._~abcdefghijklmnopqrstuvwxyz'
	. '0123456789:]',
	'IPvFuture all symbols (host header)');

is(http_absolute_path(
	'[v0123456789aBcDeF.!$&\'()*+,;=-._~AbCdEfGhIjKlMnOpQrStUvWxYz'
	. '0123456789:]'),
	'[v0123456789abcdef.!$&\'()*+,;=-._~abcdefghijklmnopqrstuvwxyz'
	. '0123456789:]',
	'IPvFuture all symbols (absolute request)');

is(http_host_header('123.40.56.78:9000:80'), '123.40.56.78',
	'double port hack');

like(http_host_header("localhost\nHost: again", 1), qr/ 400 /, 'host repeat');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.21.1');

like(http_host_header("localhost\x02", 1), qr/ 400 /, 'control');

}

###############################################################################

sub http_host_header {
	my ($host, $all) = @_;
	my ($r) = http(<<EOF);
GET / HTTP/1.0
Host: $host

EOF
	return ($all ? $r : http_content($r));
}

sub http_absolute_path {
	my ($host, $all) = @_;
	my ($r) = http(<<EOF);
GET http://$host/ HTTP/1.0
Host: localhost

EOF
	return ($all ? $r : http_content($r));
}

###############################################################################
