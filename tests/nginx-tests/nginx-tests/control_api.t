#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for Control API.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require JSON::PP; };
plan(skip_all => "JSON::PP not installed") if $@;

my $conf = <<'EOF';

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    include inc.conf;

    server {
        listen 127.0.0.1:8081;
        server_name  localhost;

        location / {
            return 200 "%%RETURN%%";
        }
    }
}

EOF

my $t = Test::Nginx->new()->has(qw/http rewrite control_api/)
	->write_file_expand('nginx.conf', $conf =~ s/%%RETURN%%/foo/r);

$t->write_file('inc.conf', '#inc.conf');

my $d = $t->testdir();
my $p = port(8080);

# Tengine uses -L for the control socket listen address: -l is already taken
# by T_NGX_SHOW_INFO to list all directives.
$t->args('-L', '127.0.0.1:' . $p)->run()->plan(96);

my $v = (sort { $a <=> $b } @{ api() })[-1];

###############################################################################

# /nginx

my $nginx = api('/nginx');
ok($t->has_version($nginx->{version}), 'nginx version');

my ($build) = $t->read_file('error.log')
	=~ /nginx\/$nginx->{version} \((.*)\)/;
$build = '' unless defined $build;
is($nginx->{build}, $build, 'nginx build');

# /processes

my $procs = api('/control/processes');
my $proc = $procs->[0];
ok($proc->{pid}, 'process pid');
ok($proc->{name}, 'process name');
is($proc->{exiting}, JSON::PP::false(), 'process running');

# /config

my $files = api('/control/config');
is(scalar @$files, 2, 'config files');

my $file = $files->[0];
ok($file->{name}, 'config filename');
like($file->{content}, qr/daemon/, 'config contents');
is($files->[1]{name}, "$d/inc.conf", 'included filename');
is($files->[1]{content}, $t->read_file('inc.conf'), 'included contents');

# endpoint listing

like(get('/'), qr/"control"/, 'root endpoints');
like(get('/control/'), qr/"processes"/, 'control endpoints');
like(get('/nginx/'), qr/"version"/, 'trailing slash');

# method validation

like(raw("POST /$v HTTP/1.0"), qr/ 405/, 'POST api ver');
like(raw("POST /$v/nginx HTTP/1.0"), qr/ 405/, 'POST nginx');
like(raw("POST /$v/control HTTP/1.0"), qr/ 405/, 'POST control');
like(raw("POST /$v/control/processes HTTP/1.0"), qr/ 405/, 'POST processes');
like(raw("POST /$v/control/config HTTP/1.0"), qr/ 405/, 'POST config');
like(raw("POST / HTTP/1.0"), qr/ 405/, 'POST root');
like(raw("POST /$v/ HTTP/1.0"), qr/ 405/, 'POST root listing');
like(raw("PURGE /$v/nginx HTTP/1.0"), qr/ 405/, 'PURGE method');
like(raw("PUT /$v/nginx HTTP/1.0"), qr/ 405/, 'PUT unsupported');
like(raw("HEAD /$v/nginx HTTP/1.0"), qr/ 405/, 'HEAD unsupported');
like(raw("DELETE /$v/nginx HTTP/1.0"), qr/ 405/, 'overlong method');
like(raw("foo /$v/ HTTP/1.0"), qr/ 400 Bad Request/, 'unknown method');
like(raw("X_Y /$v/nginx HTTP/1.0"), qr/ 405/, 'method with underscore');

# unknown endpoints

like(http_get('/2'), qr/ 404/, 'unknown api ver');
like(get('/nginy'), qr/ 404/, 'unknown nginx');
like(get('/controm'), qr/ 404/, 'unknown control');
like(get('/control/confix'), qr/ 404/, 'unknown config');
like(get('/control/processeX'), qr/ 404/, 'unknown processes');

# response headers

my $rh = get('/nginx');
like($rh, qr/Connection: close/, 'connection close');
like($rh, qr!Content-Type: application/json!, 'content-type');
like($rh, qr!Server: nginx/!, 'server header');
like(get('/nonexistent'), qr/Content-Length: 0/, 'error empty body');

# config reload

$t->write_file_expand('nginx.conf', 'bad config');

like(http_patch('/control/config'), qr/ 422/, 'reload bad config');
ok(api_patch('/control/config')->{logs}, 'reload failure has logs');
like(http_get('/', PeerAddr => '127.0.0.1:' . port(8081)), qr/foo/,
	'old config uses');

$t->write_file_expand('nginx.conf', $conf =~ s/%%RETURN%%/bar/r);

like(api('/control/config')->[0]{content}, qr/foo/, 'in memory config');
like(http_patch('/control/config'), qr/200 OK/, 'reload success');

waitforworker($t);

like(http_get('/', PeerAddr => '127.0.0.1:' . port(8081)), qr/bar/,
	'new config applied');
like(api('/control/config')->[0]{content}, qr/bar/, 'in memory config reread');
is(scalar @{ api('/control/processes') }, scalar @$procs,
	'exited processes skipped');

# connection resilience

http('', start => 1);
like(get('/nginx'), qr/200 OK/, 'healthy after abrupt close');

http("GET /$v", start => 1);
like(get('/nginx'), qr/200 OK/, 'healthy after partial request');

like(http(CRLF), qr/ 400/, 'bare CRLF rejected');

my $s = http("GET /$v/ng", start => 1, sleep => 0.2);
like(raw("inx HTTP/1.0", socket => $s), qr/"version"/,
	'request split across reads');

# accept queue drained, SIGIO coalesces while blocked

my $master = $t->read_file('nginx.pid');

kill 'STOP', $master;
my @s = map { get('/nginx', start => 1) } 1 .. 3;
kill 'CONT', $master;

my $ok = 0;
$ok++ for grep { http_end($_) =~ /"version"/ } @s;

is($ok, 3, 'accept queue drained');

# close non-last connection

my $s1 = get('/nginx', start => 1);
my $s2 = get('/nginx', start => 1);
http_end($s1);
like(http_end($s2), qr/"version"/, 'close non-last connection');

$s1 = get('/nginx', start => 1);
$s2 = get('/nginx', start => 1);
my $s3 = get('/nginx', start => 1);
http_end($s1);
like(http_end($s2), qr/"version"/, 'memmove 3 connections s2');
like(http_end($s3), qr/"version"/, 'memmove 3 connections s3');

# connection limit, the oldest connection is evicted

my @conn = map { http('', start => 1) } 1 .. 63;

like(get('/nginx'), qr/"version"/, 'served at connection limit');
ok(!get('/nginx', socket => $conn[0]), 'oldest connection evicted');
like(get('/nginx', socket => $conn[1]), qr/"version"/,
	'other connections kept');

close $_ for @conn[2 .. $#conn];

# request parsing

like(raw("GET /$v/nginx HTTP/1.1"), qr/200 OK/, 'HTTP/1.1');
like(raw("GET /$v/nginx HTTP/1.2"), qr/ 400/, 'unsupported minor ver');
like(raw("GET /$v/nginx HTTP/1.10"), qr/ 400/, 'multi-digit minor ver');
like(raw("GET /$v/nginx HTTP/2.0"), qr/ 400/, 'HTTP/2.0 rejected');
like(raw("GET /$v/nginx HTTP/1.1000"), qr/ 400/, 'minor ver overflow');
like(get('/?arg=val'), qr/ 200 OK/, 'URI args ignored');
like(raw("GET /$v/nginx"), qr/ 400/, 'HTTP/0.9 rejected');
like(raw("PATCH /$v/control/config"), qr/ 400/, 'HTTP/0.9 PATCH rejected');
like(raw("GET http://localhost/$v/nginx HTTP/1.0"), qr/ 200 OK/,
	'absolute URI');
like(raw("GET http:/localhost/$v/nginx HTTP/1.0"), qr/ 400/,
	'bad schema slashes');
like(raw("GET http:x/localhost/$v/nginx HTTP/1.0"), qr/ 400/,
	'bad schema slash');
like(raw("GET http_x://localhost/$v/nginx HTTP/1.0"), qr/ 400/,
	'bad char in schema');
like(raw("GET 1/nginx HTTP/1.0"), qr/ 400/, 'URI without slash');
like(raw("GET http://localhost HTTP/1.0"), qr/ 200 OK/, 'no path');
like(raw("GET http://localhost?arg=val HTTP/1.0"), qr/ 200 OK/,
	'no path with args');
like(raw("GET http://localhost:$p HTTP/1.0"), qr/ 200 OK/, 'no path with port');
like(raw("GET http://localhost:$p?arg=val HTTP/1.0"), qr/ 200 OK/,
	'no path with port and args');
like(raw("GET http://localhost:abc/$v/nginx HTTP/1.0"),
	qr/ 400/, 'non-numeric port');
like(raw("GET /$v/ngi%78 HTTP/1.0"), qr/ 400/, 'percent in URI');
like(raw("GET /$v/nginx# HTTP/1.0"), qr/ 400/, 'fragment in URI');
like(raw("GET   /$v/nginx HTTP/1.0"), qr/200 OK/, 'spaces before URI');
like(http("GET /$v/nginx HTTP/1.0\rX" . CRLF), qr/ 400/, 'CR no LF');
like(http(" /$v/nginx HTTP/1.0" . CRLF), qr/ 400/, 'leading space');
like(http('   ' . CRLF . CRLF), qr/ 400/, 'only spaces');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.9');

like(http('GET /' . 'x' x 1048 . CRLF), qr/ 400/, 'oversize request');
}

like(raw("GET /$v/nginx  HTTP/1.0"), qr/200 OK/, 'extra space before HTTP');
like(raw("GET /$v/nginx XTTP/1.0"), qr/ 400/, 'bad protocol');
like(raw("GET /$v/nginx HXTP/1.0"), qr/ 400/, 'bad protocol 2nd char');
like(raw("GET /$v/nginx HTXP/1.0"), qr/ 400/, 'bad protocol 3rd char');
like(raw("GET /$v/nginx HTTX/1.0"), qr/ 400/, 'bad protocol 4th char');
like(raw("GET /$v/nginx HTTP:1.0"), qr/ 400/, 'bad protocol separator');
like(raw("GET /$v/nginx HTTP/11.0"), qr/ 400/, 'multi-digit major ver');
like(http("GET /$v/nginx HTTP/1.0\n" . CRLF), qr/200 OK/, 'LF without CR');
like(raw("GET http://[::1]:$p/$v/nginx HTTP/1.0"), qr/200 OK/,
	'IPv6 literal host');
like(raw("GET http://[::1-label]/$v/nginx HTTP/1.0"), qr/200 OK/,
	'IPv6 literal with dash');
like(raw("GET http://[::1!sub]/$v/nginx HTTP/1.0"), qr/200 OK/,
	'IPv6 literal with sub-delims');
like(raw("GET http://[bad\@char]/$v/nginx HTTP/1.0"), qr/ 400/,
	'invalid char in IPv6 literal');
like(http("GET /$v/ngi\x00x HTTP/1.0" . CRLF), qr/ 400/, 'NUL byte in URI');
like(http("GE\x00T /$v/nginx HTTP/1.0" . CRLF), qr/ 400/,
	'NUL byte in method');
like(http("GET /$v/nginx\r\nX: y HTTP/1.0" . CRLF . CRLF), qr/ 400/,
	'CRLF injection in URI');
like(http("GET /$v/\xd0\xb0\xd0\xb1\xd0\xb2 HTTP/1.0" . CRLF), qr/ 404/,
	'UTF-8 bytes in URI');
like(http("\xff\xfe" . CRLF), qr/ 400/, 'binary garbage');

###############################################################################

sub api {
	my ($uri) = @_;

	$uri = defined $uri ? "/$v$uri" : '/';
	my ($body) = http_get($uri) =~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;

	return JSON::PP::decode_json($body);
}

sub api_patch {
	my ($uri) = @_;

	my ($body) = http_patch($uri) =~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;

	return JSON::PP::decode_json($body);
}

sub get {
	my ($uri, %extra) = @_;

	return http_get("/$v$uri", %extra);
}

sub http_patch {
	my ($uri, %extra) = @_;

	return http(<<EOF, %extra);
PATCH /$v$uri HTTP/1.0
Host: localhost

EOF
}

sub raw {
	my ($line, %extra) = @_;

	return http($line . CRLF . 'Host: localhost' . CRLF . CRLF, %extra);
}

sub waitforworker {
	my ($t) = @_;

	for (1 .. 30) {
		last if $t->read_file('error.log') =~ /exited with code/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
