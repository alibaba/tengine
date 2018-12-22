#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for autoindex module with autoindex_format directive.

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

my $t = Test::Nginx->new()->has(qw/http autoindex symlink/)->plan(37)
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

        autoindex on;

        location /xml/ {
            autoindex_format xml;
            alias %%TESTDIR%%/;
        }
        location /json/ {
            autoindex_format json;
            alias %%TESTDIR%%/;
        }
        location /jsonp/ {
            autoindex_format jsonp;
            alias %%TESTDIR%%/;
        }
    }
}

EOF

my $d = $t->testdir();

mkdir("$d/test-dir");
symlink("$d/test-dir", "$d/test-dir-link");

$t->write_file('test-file', 'x' x 42);
symlink("$d/test-file", "$d/test-file-link");

$t->write_file('test-\'-quote', '');
$t->write_file('test-"-double', '');
$t->write_file('test-<>-angle', '');

mkdir($d . '/utf8');
$t->write_file('utf8/test-utf8-' . ("\xd1\x84" x 3), '');
$t->write_file('utf8/test-utf8-' . ("\xd1\x84" x 45), '');

$t->run();

###############################################################################

my ($r, $mtime, $data);

$r = http_get('/xml/');
$mtime = qr/mtime="\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"/;

like($r, qr!Content-Type: text/xml; charset=utf-8!, 'xml content type');
like($r, qr!<file(\s+\w+="[^=]*?")+\s*>test-file</file>!,
	'xml file format');
like($r, qr!<directory(\s+\w+="[^=]*?")+\s*>test-dir</directory>!,
	'xml dir format');

($data) = $r =~ qr!<file\s+(.*?)>test-file</file>!;
like($data, $mtime, 'xml file mtime');
like($data, qr!size="42"!, 'xml file size');

($data) = $r =~ qr!<file\s+(.*?)>test-file-link</file>!;
like($data, $mtime, 'xml file link mtime');
like($data, qr!size="42"!, 'xml file link size');

($data) = $r =~ qr!<directory\s+(.*?)>test-dir</directory>!;
like($data, $mtime, 'xml dir mtime');
unlike($data, qr!size="\d+"!, 'xml dir size');

($data) = $r =~ qr!<directory\s+(.*?)>test-dir-link</directory>!;
like($data, $mtime, 'xml dir link mtime');
unlike($data, qr!size="\d+"!, 'xml dir link size');

like($r, qr!<file.*?>test-\'-quote</file>!, 'xml quote');
like($r, qr!<file.*?>test-\&quot;-double</file>!, 'xml double');
like($r, qr!<file.*?>test-&lt;&gt;-angle</file>!, 'xml angle');


$r = http_get('/json/');
$mtime = qr/"mtime"\s*:\s*"\w{3}, \d\d \w{3} \d{4} \d\d:\d\d:\d\d \w{3}"/;

my $string = qr!"(?:[^\\"]+|\\["\\/bfnrt])*"!;
my $number = qr!-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?!;
my $kv = qr!\s*$string\s*:\s*($string|$number)\s*!;

like($r, qr!Content-Type: application/json!, 'json content type');
like($r, qr!{$kv(,$kv)*}!, 'json format');

($data) = $r =~ qr!(\{[^}]*?"name"\s*:\s*"test-file".*?})!;
like($data, qr!"type"\s*:\s*"file"!, 'json file');
like($data, $mtime, 'json file mtime');
like($data, qr!"size"\s*:\s*42!, 'json file size');

($data) = $r =~ qr!(\{[^}]*?"name"\s*:\s*"test-file-link".*?})!;
like($data, qr!"type"\s*:\s*"file"!, 'json file link');
like($data, $mtime, 'json file link mtime');
like($data, qr!"size"\s*:\s*42!, 'json file link size');

($data) = $r =~ qr!(\{[^}]*?"name"\s*:\s*"test-dir".*?})!;
like($data, qr!"type"\s*:\s*"directory"!, 'json dir');
like($data, $mtime, 'json dir mtime');
unlike($data, qr!"size"\s*:\s*$number!, 'json dir size');

($data) = $r =~ qr!(\{[^}]*?"name"\s*:\s*"test-dir-link".*?})!;
like($data, qr!"type"\s*:\s*"directory"!, 'json dir link');
like($data, $mtime, 'json dir link mtime');
unlike($data, qr!"size"\s*:\s*$number!, 'json dir link size');

like($r, qr!"name"\s*:\s*"test-'-quote"!, 'json quote');
like($r, qr!"name"\s*:\s*"test-\\\"-double"!, 'json double');
like($r, qr!"name"\s*:\s*"test-<>-angle"!, 'json angle');

like(http_get_body('/jsonp/test-dir/?callback=foo'),
	qr/^\s*foo\s*\(\s*\[\s*\]\s*\)\s*;\s*$/ms, 'jsonp callback');
like(http_get_body('/jsonp/test-dir/?callback='),
	qr/^\s*\[\s*\s*\]\s*$/ms, 'jsonp callback empty');

# utf8 tests

$r = http_get('/xml/utf8/');
like($r, qr!test-utf8-(\xd1\x84){3}</file>!ms, 'xml utf8');
like($r, qr!test-utf8-(\xd1\x84){45}</file>!ms, 'xml utf8 long');

$r = http_get('/json/utf8/');
like($r, qr!test-utf8-(\xd1\x84){3}"!ms, 'json utf8');
like($r, qr!test-utf8-(\xd1\x84){45}"!ms, 'json utf8 long');

###############################################################################

sub http_get_body {
	my ($uri) = @_;

	return undef if !defined $uri;

	http_get($uri) =~ /(.*?)\x0d\x0a?\x0d\x0a?(.*)/ms;

	return $2;
}

###############################################################################
