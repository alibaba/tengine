#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with request body, additional tests.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy rewrite cryptx/)
	->has_daemon('openssl')->plan(50);

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

        client_header_buffer_size 1k;
        client_body_buffer_size 2k;

        location / {
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
            proxy_pass http://127.0.0.1:8082;
        }

        location /file {
            client_body_in_file_only on;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8082;
        }

        location /single {
            client_body_in_single_buffer on;
            add_header X-Body "$request_body";
            add_header X-Body-File "$request_body_file";
            proxy_pass http://127.0.0.1:8082;
        }

        location /large {
            client_max_body_size 1k;
            proxy_pass http://127.0.0.1:8082;
        }

        location /unbuf/ {
            add_header X-Unbuf-File "$request_body_file";
            proxy_pass http://127.0.0.1:8081/;
            proxy_request_buffering off;
            proxy_http_version 1.1;
        }
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;
        return 204;
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

$t->run();

###############################################################################

# below are basic body tests from body.t, slightly
# adapted to HTTP/3, repeated multiple times with variations:
#
# buffered vs. non-buffered, length vs. chunked,
# single frame vs. multiple frames
#
# some does not make sense in HTTP/3 (such as "body in two buffers"), but
# preserved for consistency and due to the fact that proxying via HTTP/1.1
# is used in unbuffered tests

unlike(http3_get('/'), qr/x-body:/ms, 'no body');

like(http3_get_body('/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body');
like(http3_get_body('/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body in two buffers');
like(http3_get_body('/', '0123456789' x 512),
	qr/x-body-file/ms, 'body in file');
like(read_body_file(http3_get_body('/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body in file only');
like(http3_get_body('/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body in single buffer');
like(http3_get_body('/large', '0123456789' x 128),
	qr/:status: 413/, 'body too large');

# without Content-Length header

like(http3_get_body_nolen('/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body nolen');
like(http3_get_body_nolen('/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body nolen in two buffers');
like(http3_get_body_nolen('/', '0123456789' x 512),
	qr/x-body-file/ms, 'body nolen in file');
like(read_body_file(http3_get_body_nolen('/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body nolen in file only');
like(http3_get_body_nolen('/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body nolen in single buffer');
like(http3_get_body_nolen('/large', '0123456789' x 128),
	qr/:status: 413/, 'body nolen too large');

# with multiple frames

like(http3_get_body_multi('/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body multi');
like(http3_get_body_multi('/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body multi in two buffers');
like(http3_get_body_multi('/', '0123456789' x 512),
	qr/x-body-file/ms, 'body multi in file');
like(read_body_file(http3_get_body_multi('/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body multi in file only');
like(http3_get_body_multi('/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body multi in single buffer');
like(http3_get_body_multi('/large', '0123456789' x 128),
	qr/:status: 413/, 'body multi too large');

# with multiple frames and without Content-Length header

like(http3_get_body_multi_nolen('/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body multi nolen');
like(http3_get_body_multi_nolen('/', '0123456789' x 128),
	qr/x-body: (0123456789){128}/ms, 'body multi nolen in two buffers');
like(http3_get_body_multi_nolen('/', '0123456789' x 512),
	qr/x-body-file/ms, 'body multi nolen in file');
like(read_body_file(http3_get_body_multi_nolen('/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body multi nolen in file only');
like(http3_get_body_multi_nolen('/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body multi nolen in single buffer');
like(http3_get_body_multi_nolen('/large', '0123456789' x 128),
	qr/:status: 413/, 'body multi nolen too large');

# unbuffered

unlike(http3_get('/unbuf/'), qr/x-body:/ms, 'no body unbuf');

like(http3_get_body('/unbuf/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body unbuf');
like(http3_get_body('/unbuf/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf in two buffers');
like(http3_get_body('/unbuf/', '0123456789' x 512),
	qr/(?!.*x-unbuf-file.*)x-body-file/ms, 'body unbuf in file');
like(read_body_file(http3_get_body('/unbuf/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body unbuf in file only');
like(http3_get_body('/unbuf/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf in single buffer');
like(http3_get_body('/unbuf/large', '0123456789' x 128),
	qr/:status: 413/, 'body unbuf too large');

# unbuffered without Content-Length

like(http3_get_body_nolen('/unbuf/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body unbuf nolen');
like(http3_get_body_nolen('/unbuf/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf nolen in two buffers');
like(http3_get_body_nolen('/unbuf/', '0123456789' x 512),
	qr/(?!.*x-unbuf-file.*)x-body-file/ms, 'body unbuf nolen in file');
like(read_body_file(http3_get_body_nolen('/unbuf/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body unbuf nolen in file only');
like(http3_get_body_nolen('/unbuf/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf nolen in single buffer');
like(http3_get_body_nolen('/unbuf/large', '0123456789' x 128),
	qr/:status: 413/, 'body unbuf nolen too large');

# unbuffered with multiple frames

like(http3_get_body_multi('/unbuf/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body unbuf multi');
like(http3_get_body_multi('/unbuf/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf multi in two buffers');
like(http3_get_body_multi('/unbuf/', '0123456789' x 512),
	qr/(?!.*x-unbuf-file.*)x-body-file/ms, 'body unbuf multi in file');
like(read_body_file(http3_get_body_multi('/unbuf/file', '0123456789' x 512)),
	qr/^(0123456789){512}$/s, 'body unbuf multi in file only');
like(http3_get_body_multi('/unbuf/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms, 'body unbuf multi in single buffer');
like(http3_get_body_multi('/unbuf/large', '0123456789' x 128),
	qr/:status: 413/, 'body unbuf multi too large');

# unbuffered with multiple frames and without Content-Length

like(http3_get_body_multi_nolen('/unbuf/', '0123456789'),
	qr/x-body: 0123456789$/ms, 'body unbuf multi nolen');
like(http3_get_body_multi_nolen('/unbuf/', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms,
	'body unbuf multi nolen in two buffers');
like(http3_get_body_multi_nolen('/unbuf/', '0123456789' x 512),
	qr/(?!.*x-unbuf-file.*)x-body-file/ms,
	'body unbuf multi nolen in file');
like(read_body_file(http3_get_body_multi_nolen('/unbuf/file',
	'0123456789' x 512)), qr/^(0123456789){512}$/s,
	'body unbuf multi nolen in file only');
like(http3_get_body_multi_nolen('/unbuf/single', '0123456789' x 128),
	qr/x-body: (0123456789){128}$/ms,
	'body unbuf multi nolen in single buffer');
like(http3_get_body_multi_nolen('/unbuf/large', '0123456789' x 128),
	qr/:status: 413/, 'body unbuf multi nolen too large');

###############################################################################

sub http3_get {
	my ($uri) = @_;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $uri });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;

	return join("\n", map { "$_: " . $frame->{headers}->{$_}; }
		keys %{$frame->{headers}});
}

sub http3_get_body {
	my ($uri, $body) = @_;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $uri, body => $body });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;

	return join("\n", map { "$_: " . $frame->{headers}->{$_}; }
			keys %{$frame->{headers}});
}

sub http3_get_body_nolen {
	my ($uri, $body) = @_;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $uri, body_more => 1 });
	$s->h3_body($body, $sid);
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;

	return join("\n", map { "$_: " . $frame->{headers}->{$_}; }
			keys %{$frame->{headers}});
}

sub http3_get_body_multi {
	my ($uri, $body) = @_;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({
		headers => [
			{ name => ':method', value => 'GET' },
			{ name => ':scheme', value => 'http' },
			{ name => ':path', value => $uri },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-length', value => length $body },
		],
		body_more => 1
	});
	for my $b (split //, $body, 10) {
		$s->h3_body($b, $sid, { body_more => 1 });
	}
	$s->h3_body('', $sid);
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;

	return join("\n", map { "$_: " . $frame->{headers}->{$_}; }
			keys %{$frame->{headers}});
}

sub http3_get_body_multi_nolen {
	my ($uri, $body) = @_;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ path => $uri, body_more => 1 });
	for my $b (split //, $body, 10) {
		$s->h3_body($b, $sid, { body_more => 1 });
	}
	$s->h3_body('', $sid);
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;

	return join("\n", map { "$_: " . $frame->{headers}->{$_}; }
			keys %{$frame->{headers}});
}

sub read_body_file {
	my ($r) = @_;
	return '' unless $r =~ m/x-body-file: (.*)/;
	open FILE, $1
		or return "$!";
	local $/;
	my $content = <FILE>;
	close FILE;
	return $content;
}

###############################################################################
