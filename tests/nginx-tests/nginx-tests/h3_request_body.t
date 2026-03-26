#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with request body.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy cryptx/)
	->has_daemon('openssl')->plan(30);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        listen       127.0.0.1:8081;
        server_name  localhost;

        error_page 400 /proxy/t.html;

        location / {
            add_header X-Length $http_content_length;
        }
        location /off/ {
            proxy_pass http://127.0.0.1:8081/;
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
        }
        location /proxy/ {
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

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', '');
$t->write_file('t.html', 'SEE-THIS');
$t->run();

###############################################################################

# request body (uses proxied response)

my $s = Test::Nginx::HTTP3->new();
my $sid = $s->new_stream({ path => '/proxy/t.html', body => 'TEST' });
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST', 'request body');
is($frame->{headers}->{'x-length'}, 4, 'request body - content length');

# request body sent in multiple DATA frames in a single packet

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream(
	{ path => '/proxy/t.html', body => 'TEST', body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST',
	'request body in multiple frames');
is($frame->{headers}->{'x-length'}, 4,
	'request body in multiple frames - content length');

# request body sent in multiple DATA frames, each in its own packet

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/proxy/t.html', body_more => 1 });
$s->h3_body('TEST', $sid, { body_more => 1 });
$s->h3_body('MOREDATA', $sid);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTMOREDATA',
	'request body in multiple frames separately');
is($frame->{headers}->{'x-length'}, 12,
	'request body in multiple frames separately - content length');

# request body with an empty DATA frame

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/proxy/', body => '' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request body - empty');
is($frame->{headers}->{'x-length'}, 0, 'request body - empty size');
ok($frame->{headers}{'x-body-file'}, 'request body - empty body file');
is(read_body_file($frame->{headers}{'x-body-file'}), '',
	'request body - empty content');

# it is expected to avoid adding Content-Length for requests without body

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/proxy/' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request without body');
is($frame->{headers}->{'x-length'}, undef,
	'request without body - content length');

# request body discarded
# expected STOP_SENDING with zero code, stream cancellation

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body_more => 1 });
$frames = $s->read(all => [
	{ type => 'STOP_SENDING' },
	{ type => 'DECODER_C' }
]);

($frame) = grep { $_->{type} eq "STOP_SENDING" } @$frames;
is($frame->{code}, 0x100, 'request body discarded - STOP_SENDING no error');

($frame) = grep { $_->{type} eq "DECODER_C" } @$frames;
is($frame->{val}, $sid, 'request body discarded - stream cancellation');

# malformed request body length not equal to content-length

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body => 'TEST', headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' },
	{ name => 'content-length', value => '5' }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'request body less than content-length');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.27.0');

$sid = $s->new_stream({ body => 'TEST', headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' },
	{ name => 'content-length', value => '3' }]});
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 400, 'request body more than content-length');

}

# client_max_body_size

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body => 'TESTTEST12' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'client_max_body_size - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size - body');

# client_max_body_size - limited

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body => 'TESTTEST123' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413, 'client_max_body_size - limited');

# client_max_body_size - many DATA frames

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body => 'TESTTEST12', body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'client_max_body_size many - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'client_max_body_size many - body');

# client_max_body_size - many DATA frames - limited

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/client_max_body_size/t.html',
	body => 'TESTTEST123', body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413, 'client_max_body_size many - limited');

# request body without content-length

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' }]});
$s->h3_body('TESTTEST12', $sid);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'request body without content-length - body');

# request body without content-length - limited

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' }]});
$s->h3_body('TESTTEST123', $sid);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length - limited');

# request body without content-length - many DATA frames

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' }]});
$s->h3_body('TESTTEST12', $sid, { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200,
	'request body without content-length many - status');
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TESTTEST12',
	'request body without content-length many - body');

# request body without content-length - many DATA frames - limited

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body_more => 1, headers => [
	{ name => ':method', value => 'GET' },
	{ name => ':scheme', value => 'http' },
	{ name => ':path', value => '/client_max_body_size' },
	{ name => ':authority', value => 'localhost' }]});
$s->h3_body('TESTTEST123', $sid, { body_split => [2] });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 413,
	'request body without content-length many - limited');

# absent request body is not buffered with client_body_in_file_only off
# see 27c7ed683 for details

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/off/t.html' });
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{'x-body-file'}, undef, 'no request body in file');

# request body after 400 errors redirected to a proxied location

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ body => "", headers => [
	{ name => ':method', value => "" }]});

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
($frame) = grep { $_->{type} eq 'DATA' } @$frames;
is($frame->{data}, 'SEE-THIS', 'request body after 400 redirect');

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
