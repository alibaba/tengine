#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 backend response headers.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/);

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
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 2;
        }

        location /field {
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 2;
            proxy_buffer_size 65k;
            proxy_busy_buffers_size 65k;
            proxy_buffers 8 16k;
        }

        location /continuation {
            proxy_pass http://127.0.0.1:8081$uri;
            proxy_http_version 2;
            proxy_set_header X-LongHeader1 $arg_h$arg_h;
            proxy_set_header X-LongHeader2 $arg_h$arg_h;
            proxy_set_header X-LongHeader3 $arg_h$arg_h;
            proxy_set_header X-LongHeader4 $arg_h$arg_h;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(19);

###############################################################################

# various header compression formats

like(http_get('/mode/0'), qr/200 OK/, 'indexed');
like(http_get('/mode/1'), qr/200 OK/, 'inc indexing');
like(http_get('/mode/2'), qr/200 OK/, 'inc indexing new');
like(http_get('/mode/3'), qr/200 OK/, 'without indexing');
like(http_get('/mode/4'), qr/200 OK/, 'without indexing new');
like(http_get('/mode/5'), qr/200 OK/, 'never indexed');
like(http_get('/mode/6'), qr/200 OK/, 'never indexed new');
like(http_get('/huffman'), qr/200 OK/, 'huffman');

like(http_get('/update/0'), qr/200 OK/, 'dynamic table size 0');
like(http_get('/update/1'), qr/502 Bad/, 'dynamic table size 1');

like(http_get('/field/0'), qr/502 Bad/, 'zero header field');
like(http_get('/field/7'), qr/200 OK/, 'long header field 1');
like(http_get('/field/8'), qr/200 OK/, 'long header field 2');
like(http_get('/field/15'), qr/200 OK/, 'long header field 3');
like(http_get('/field/16'), qr/502 Bad/, 'long header field 4');

# padding & priority

like(http_get('/padding'), qr/200 OK/, 'padding');
like(http_get('/priority'), qr/200 OK/, 'priority');
like(http_get('/priopad'), qr/200 OK/, 'padding priority');

# continuation to backend, headers chunked by NGX_HTTP_V2_DEFAULT_FRAME_SIZE

like(http_get('/continuation?h=' . ('Z' x 4096)),
	qr/200 OK.*x-continuation: 2.*8192 8192 8192 8192/s, 'continuation');

###############################################################################

sub http_daemon {
	my $client;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $ccount = 0;

	while ($client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface
		$ccount++;

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		my $frames = $c->read(all => [{ fin => 4 }]);
		my ($frame) =
			grep { $_->{type} =~ "HEADERS|CONTINUATION"
				&& ($_->{flags} & 4) }
			@$frames;
		my $sid = $frame->{sid};
		my $uri = $frame->{headers}{':path'};

		if ($uri =~ m|mode/(\d)|) {
			my $mode = $1;

			$c->new_stream({ headers => [
				{ name => ':status', value => '200',
					mode => $mode },
				{ name => 'server', value => '',
					mode => $mode },
			]}, $sid);

		} elsif ($uri =~ m/huffman/) {
			$c->new_stream({ headers => [
				{ name => ':status', value => '200',
					mode => 2, huff => 1 },
				{ name => 'server', value => '',
					mode => 2, huff => 1 },
			]}, $sid);

		} elsif ($uri =~ m|update/(\d)|) {
			my $update = $1;

			$c->new_stream({ table_size => $update, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);

		} elsif ($uri =~ m|field/(\d+)|) {
			my $flen = $1 ? 2**$1 : 0;
			my $cont = [ map {2**14} (0..$flen/2**13) ]
				if $flen > 2**13;

			$c->new_stream({ continuation => $cont, headers => [
				{ name => ':status', value => '200' },
				{ name => 'x' x $flen, value => 'y' x $flen,
					mode => 2 }
			]}, $sid);

		} elsif ($uri eq '/padding') {
			$c->new_stream({ padding => 7, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);

		} elsif ($uri eq '/priority') {
			$c->new_stream({ prio => 137, dep => 0x01020304,
				headers => [
				{ name => ':status', value => '200' },
			]}, $sid);

		} elsif ($uri eq '/priopad') {
			$c->new_stream({ prio => 137, dep => 0x01020304,
				padding => 7, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);

		} elsif ($uri eq '/continuation') {
			my $ccount = grep { $_->{type} =~ "CONTINUATION" }
				@$frames;

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
				{ name => 'x-continuation', value => $ccount,
					mode => 2 },
			]}, $sid);
			$c->h2_body(join ' ',
				length($frame->{headers}{'x-longheader1'}),
				length($frame->{headers}{'x-longheader2'}),
				length($frame->{headers}{'x-longheader3'}),
				length($frame->{headers}{'x-longheader4'}));

		} else {
			$c->new_stream({ headers => [
				{ name => ':status', value => '404' },
			]}, $sid);
		}
	}
}

###############################################################################
