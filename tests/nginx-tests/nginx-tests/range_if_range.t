#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for range filter module with If-Range header.

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

my $t = Test::Nginx->new()->has(qw/http/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t2.html {
            add_header Last-Modified "";
        }

        location /t3.html {
            add_header Last-Modified "Mon, 28 Sep 1970 06:00:00 GMT";
        }
    }
}

EOF

$t->write_file('t1.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t2.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->write_file('t3.html',
	join('', map { sprintf "X%03dXXXXXX", $_ } (0 .. 99)));
$t->run();

###############################################################################

my $t1;

# If-Range

$t1 = http_get_range('/t1.html', "Range: bytes=0-9\nIf-Range: wrong");
like($t1, qr/200 OK/, 'if-range wrong');
like($t1, qr/Last-Modified: /, 'if-range wrong - last modified');

$t1 =~ m/Last-Modified: (.*)/m;
my $last = $1;

$t1 = http_get_range('/t1.html', "Range: bytes=0-9\nIf-Range: $last");
like($t1, qr/206/, 'if-range');

# If-Range + add_header Last-Modified ""

$t1 = http_get_range('/t2.html', "Range: bytes=0-9\nIf-Range: wrong");

TODO: {
local $TODO = 'not yet';

like($t1, qr/200 OK/, 'if-range notime');

}

unlike($t1, qr/Last-Modified: /, 'if-range notime - no last modified');

# If-Range + add_header Last-Modified "Mon, 28 Sep 1970 06:00:00 GMT"

$t1 = http_get_range('/t3.html', "Range: bytes=0-9\nIf-Range: wrong");

TODO: {
local $TODO = 'not yet';

like($t1, qr/200 OK/, 'if-range time wrong');

}

like($t1, qr/Last-Modified: Mon, 28 Sep 1970 06:00:00 GMT/,
	'if-range time wrong - last modified');

$t1 = http_get_range('/t3.html',
	"Range: bytes=0-9\nIf-Range: Mon, 28 Sep 1970 06:00:00 GMT");

TODO: {
local $TODO = 'requires add_header changes after if-range fix';

like($t1, qr/206/, 'if-range time');

}

###############################################################################

sub http_get_range {
	my ($url, $extra) = @_;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
$extra

EOF
}

###############################################################################
