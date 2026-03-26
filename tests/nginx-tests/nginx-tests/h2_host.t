#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for host parsing in requests.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 rewrite/)->plan(60);

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

        http2 on;

        location / {
            return  200  $host;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_host_header('', 1), qr / 400 /,
	'domain empty (host header)');
like(http_absolute_path('', 1), qr / 400 /,
	'domain empty (absolute request)');

is(http_host_header('l'), 'l',
	'domain single (host header)');
is(http_absolute_path('l'), 'l',
	'domain single (absolute request)');

is(http_host_header('L'), 'l',
	'domain single upper (host header)');
is(http_absolute_path('L'), 'l',
	'domain single upper (absolute request)');


is(http_host_header('abcd-ef.g02.xyz:'), 'abcd-ef.g02.xyz',
	'domain stray colon (host header)');
is(http_absolute_path('abcd-ef.g02.xyz:'), 'abcd-ef.g02.xyz',
	'domain stray colon (absolute request)');

is(http_host_header('123.40.56.78:'), '123.40.56.78',
	'ipv4 stray colon (host header)');
is(http_absolute_path('123.49.0.78:'), '123.49.0.78',
	'ipv4 stray colon (absolute request)');


is(http_host_header('www.abcd-ef.g02.xyz'), 'www.abcd-ef.g02.xyz',
	'domain w/o port (host header)');
is(http_host_header('abcd-ef.g02.xyz:8080'), 'abcd-ef.g02.xyz',
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

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_host_header('example.com.:1.2', 1), qr/ 400 /,
	'domain w/ ending dot w/port dot (host header)');

}

like(http_host_header('.', 1), qr/ 400 /,
	'empty domain w/ ending dot (host header)');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_absolute_path('example.com.:1.2', 1), qr/ 400 /,
	'domain w/ ending dot w/port dot (absolute request)');

}

like(http_absolute_path('.', 1), qr/ 400 /,
	'empty domain w/ ending dot (absolute request)');


is(http_absolute_path('AbC-d93.0.34ZhGt-s.nk.Ru'), 'abc-d93.0.34zhgt-s.nk.ru',
	'mixed case domain w/o port (absolute request)');
is(http_host_header('AbC-d93.0.34ZhGt-s.nk.Ru:88'), 'abc-d93.0.34zhgt-s.nk.ru',
	'mixed case domain w/port (host header)');


is(http_host_header('123.40.56.78'), '123.40.56.78',
	'ipv4 w/o port (host header)');
is(http_host_header('123.49.0.78:987'), '123.49.0.78',
	'ipv4 w/port (host header)');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_host_header('123.49.0.78:98777', 1), qr/ 400 /,
	'ipv4 w/port long (host header)');
like(http_host_header('123.40.56.78:9000:80', 1), qr/ 400 /,
	'ipv4 w/port double (host header)');

}

is(http_absolute_path('123.49.0.78'), '123.49.0.78',
	'ipv4 w/o port (absolute request)');
is(http_absolute_path('123.40.56.78:123'), '123.40.56.78',
	'ipv4 w/port (absolute request)');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_absolute_path('123.40.56.78:123456', 1), qr/ 400 /,
	'ipv4 w/port long (absolute request)');
like(http_absolute_path('123.40.56.78:9000:80', 1), qr/ 400 /,
	'ipv4 w/port double (absolute request)');

}

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

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_host_header('[abcd::ef98:0:7654:321].', 1), qr/ 400 /,
	'ipv6 literal w/ ending dot w/o port(host header)');
like(http_host_header('[abcd::ef98:0:7654:321].:98', 1), qr/ 400 /,
	'ipv6 literal w/ ending dot w/port (host header)');

like(http_absolute_path('[abcd::ef98:0:7654:321].', 1), qr/ 400 /,
	'ipv6 literal w/ ending dot w/o port(absolute request)');
like(http_absolute_path('[abcd::ef98:0:7654:321].:98', 1), qr/ 400 /,
	'ipv6 literal w/ ending dot w/port (absolute request)');

}

like(http_host_header('[abcd::ef98:0:7654:321]..:98', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (host header)');
like(http_absolute_path('[ab..cd::ef98:0:7654:321]', 1), qr/ 400 /,
	'ipv6 literal w/ double dot (absolute request)');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.4');

like(http_host_header('extra[abcd::ef98:0:7654:321]:98', 1), qr/ 400 /,
	'ipv6 literal w/ leading alnum (host header)');
like(http_absolute_path('extra[abcd::ef98:0:7654:321]', 1), qr/ 400 /,
	'ipv6 literal w/ leading alnum (absolute request)');

like(http_host_header('[abcd::ef98:0:7654:321', 1), qr/ 400 /,
	'ipv6 literal missing bracket (host header)');
like(http_absolute_path('[abcd::ef98:0:7654:321', 1), qr/ 400 /,
	'ipv6 literal missing bracket (absolute request)');

}

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

like(http_host_header("localhost", 1, 1), qr/ 400 /, 'host repeat');
like(http_host_header("localhost\x02", 1), qr/ 400 /, 'control');

###############################################################################

sub http_host_header {
	my ($host, $all, $dup) = @_;

	my $s = Test::Nginx::HTTP2->new();
	my $sid = $s->new_stream({ headers => [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/', mode => 0 },
		{ name => 'host', value => $host, mode => 1 },
		$dup ?
		{ name => 'host', value => 'again', mode => 1 }
		: ()
	]});
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($headers) = grep { $_->{type} eq "HEADERS" } @$frames;
	my ($data) = grep { $_->{type} eq "DATA" } @$frames;
	$all ? ' ' . $headers->{headers}{':status'} . ' ' : $data->{data};
}

sub http_absolute_path {
	my ($host, $all) = @_;
	my $s = Test::Nginx::HTTP2->new();
	my $sid = $s->new_stream({ headers => [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/', mode => 0 },
		{ name => ':authority', value => $host, mode => 1 }]});
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($headers) = grep { $_->{type} eq "HEADERS" } @$frames;
	my ($data) = grep { $_->{type} eq "DATA" } @$frames;
	$all ? ' ' . $headers->{headers}{':status'} . ' ' : $data->{data};
}

###############################################################################
