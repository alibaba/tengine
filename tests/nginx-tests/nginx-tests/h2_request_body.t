#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with request body.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/)->plan(44);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Length $http_content_length;
        }
        location /slow {
            limit_rate 100;
        }
        location /off/ {
            proxy_pass http://127.0.0.1:8081/;
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
        }
        location /proxy2/ {
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
            client_body_in_file_only on;
            proxy_pass http://127.0.0.1:8081/;
        }
        location /client_max_body_size {
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
            client_body_in_single_buffer on;
            client_body_in_file_only on;
            proxy_pass http://127.0.0.1:8081/;
            client_max_body_size 10;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('t.html', 'SEE-THIS');
$t->write_file('slow.html', 'SEE-THIS');
$t->run();

###############################################################################

# request body (uses proxied response)

my $s = Test::Nginx::HTTP2->new();
my $sid = $s->new_stream({ path => '/proxy2/t.html', body_more => 1 });
$s->h2_body('TEST');
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST', 'request body');
is($frame->{headers}->{'x-length'}, 4, 'request body - content length');

# request body with padding (uses proxied response)

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy2/t.html', body_more => 1 });
$s->h2_body('TEST', { body_padding => 42 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST',
	'request body with padding');
is($frame->{headers}->{'x-length'}, 4,
	'request body with padding - content length');

$sid = $s->new_stream();
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, '200', 'request body with padding - next');

# request body sent in multiple DATA frames in a single packet

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy2/t.html', body_more => 1 });
$s->h2_body('TEST', { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST',
	'request body in multiple frames');
is($frame->{headers}->{'x-length'}, 4,
	'request body in multiple frames - content length');

# request body sent in multiple DATA frames, each in its own packet

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy2/t.html', body_more => 1 });
$s->h2_body('TEST', { body_more => 1 });
select undef, undef, undef, 0.1;
$s->h2_body('MOREDATA');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTMOREDATA',
	'request body in multiple frames separately');
is($frame->{headers}->{'x-length'}, 12,
	'request body in multiple frames separately - content length');

# request body with an empty DATA frame
# "zero size buf in output" alerts seen

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy2/', body_more => 1 });
$s->h2_body('');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request body - empty');
is($frame->{headers}->{'x-length'}, 0, 'request body - empty size');
ok($frame->{headers}{'x-body-file'}, 'request body - empty body file');
is(read_body_file($frame->{headers}{'x-body-file'}), '',
	'request body - empty content');

# it is expected to avoid adding Content-Length for requests without body

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/proxy2/' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request without body');
is($frame->{headers}->{'x-length'}, undef,
	'request without body - content length');

# request body discarded
# RST_STREAM with zero code received

TODO: {
local $TODO = 'not yet';

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1 });
$frames = $s->read(all => [{ type => 'RST_STREAM' }], wait => 0.5);

($frame) = grep { $_->{type} eq "RST_STREAM" } @$frames;
is($frame->{code}, 0, 'request body discarded - zero RST_STREAM');

}

# malformed request body length not equal to content-length

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/client_max_body_size', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'content-length', value => '5', mode => 1 }]});
$s->h2_body('TEST');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'request body less than content-length');

$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 0 },
	{ name => ':scheme', value => 'http', mode => 0 },
	{ name => ':path', value => '/client_max_body_size', mode => 1 },
	{ name => ':authority', value => 'localhost', mode => 1 },
	{ name => 'content-length', value => '3', mode => 1 }]});
$s->h2_body('TEST');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'request body more than content-length');

# client_max_body_size

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST12');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'client_max_body_size - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size - body');

# client_max_body_size - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST123');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413, 'client_max_body_size - limited');

# client_max_body_size - many DATA frames

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST12', { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'client_max_body_size many - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size many - body');

# client_max_body_size - many DATA frames - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST123', { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413, 'client_max_body_size many - limited');

# client_max_body_size - padded DATA

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST12', { body_padding => 42 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'client_max_body_size pad - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size pad - body');

# client_max_body_size - padded DATA - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST123', { body_padding => 42 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413, 'client_max_body_size pad - limited');

# client_max_body_size - many padded DATA frames

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST12', { body_padding => 42, body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'client_max_body_size many pad - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size many pad - body');

# client_max_body_size - many padded DATA frames - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body_more => 1 });
$s->h2_body('TESTTEST123', { body_padding => 42, body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'client_max_body_size many pad - limited');

# request body without content-length

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST12');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'request body without content-length - body');

# request body without content-length - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST123');
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length - limited');

# request body without content-length - many DATA frames

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST12', { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length many - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'request body without content-length many - body');

# request body without content-length - many DATA frames - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST123', { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length many - limited');

# request body without content-length - padding

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST12', { body_padding => 42 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length pad - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'request body without content-length pad - body');

# request body without content-length - padding - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST123', { body_padding => 42 });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length pad - limited');

# request body without content-length - padding with many DATA frames

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST', { body_padding => 42, body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length many pad - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST',
	'request body without content-length many pad - body');

# request body without content-length - padding with many DATA frames - limited

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET', mode => 2 },
	{ name => ':scheme', value => 'http', mode => 2 },
	{ name => ':path', value => '/client_max_body_size', mode => 2 },
	{ name => ':authority', value => 'localhost', mode => 2 }]});
$s->h2_body('TESTTEST123', { body_padding => 42, body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length many pad - limited');

# absent request body is not buffered with client_body_in_file_only off
# see e02f1977846b for details

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/off/t.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body-file'}, undef, 'no request body in file');

# ticket #1384, request body corruption in recv_buffer

$s = Test::Nginx::HTTP2->new();
$sid = $s->new_stream({ path => '/off/slow.html', body_more => 1 });
select undef, undef, undef, 0.1;

# for simplicity, DATA frame is received on its own for a known offset

$s->h2_body('TEST');
select undef, undef, undef, 0.1;

# overwrite recv_buffer; since upstream response arrival is delayed,
# this would make $request_body point to the overridden buffer space

$s->h2_ping('xxxx');

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
isnt($frame->{headers}->{'x-body'}, 'xxxx', 'sync buffer');

###############################################################################

sub read_body_file {
	my ($path) = @_;
	open FILE, $path or return "$!";
	local $/;
	my $content = <FILE>;
	close FILE;
	return $content;
}

###############################################################################
