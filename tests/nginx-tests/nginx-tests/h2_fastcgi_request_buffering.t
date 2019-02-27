#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 protocol with unbuffered request body and fastcgi backend.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 fastcgi/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        location / {
            fastcgi_request_buffering off;
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
            client_body_buffer_size 1k;
        }
    }
}

EOF

$t->run();
$t->plan(48);

###############################################################################

# unbuffered request body to fastcgi

my $f = get_body('/');
ok($f->{headers}, 'request');
is($f->{upload}('01234', body_more => 1), '01234', 'part');
is($f->{upload}('56789'), '56789_eos', 'part 2');
is($f->{http_end}(), 200, 'response');

$f = get_body('/');
ok($f->{headers}, 'buffer');
is($f->{upload}('0123' x 128, body_more => 1), '0123' x 128, 'buffer - below');
is($f->{upload}('4567' x 128, body_more => 1), '4567' x 128, 'buffer - equal');
is($f->{upload}('89AB' x 128), '89AB' x 128 . '_eos', 'buffer - above');
is($f->{http_end}(), 200, 'buffer - response');

$f = get_body('/');
ok($f->{headers}, 'many');
is($f->{upload}('01234many', body_split => [ 5 ], body_more => 1),
	'01234many', 'many - part');
is($f->{upload}('56789many', body_split => [ 5 ]),
	'56789many_eos', 'many - part 2');
is($f->{http_end}(), 200, 'many - response');

$f = get_body('/');
ok($f->{headers}, 'empty');
is($f->{upload}('', body_more => 1, wait => 0.2), '', 'empty - part');
is($f->{upload}(''), '_eos', 'empty - part 2');
is($f->{http_end}(), 200, 'empty - response');

$f = get_body('/');
ok($f->{headers}, 'split');
is($f->{upload}('0123456789', split => [ 14 ]), '0123456789_eos',
	'split - part');
is($f->{http_end}(), 200, 'split - response');

# unbuffered request body to fastcgi, content-length

$f = get_body('/', 'content-length' => 10);
ok($f->{headers}, 'cl');

is($f->{upload}('01234', body_more => 1), '01234', 'cl - part');
is($f->{upload}('56789'), '56789_eos', 'cl - part 2');
is($f->{http_end}(), 200, 'cl - response');

$f = get_body('/', 'content-length' => 1536);
ok($f->{headers}, 'cl buffer');
is($f->{upload}('0123' x 128, body_more => 1), '0123' x 128,
	'cl buffer - below');
is($f->{upload}('4567' x 128, body_more => 1), '4567' x 128,
	'cl buffer - equal');
is($f->{upload}('89AB' x 128), '89AB' x 128 . '_eos', 'cl buffer - above');
is($f->{http_end}(), 200, 'cl buffer - response');

$f = get_body('/', 'content-length' => 10);
ok($f->{headers}, 'cl much');
is($f->{upload}('0123456789', body_more => 1), '0123456789', 'cl much - part');
is($f->{upload}('many'), '', 'cl much - part 2');
is($f->{http_end}(), 400, 'cl much - response');

$f = get_body('/', 'content-length' => 10);
ok($f->{headers}, 'cl less');
is($f->{upload}('0123', body_more => 1), '0123', 'cl less - part');
is($f->{upload}('56789'), '', 'cl less - part 2');
is($f->{http_end}(), 400, 'cl less - response');

$f = get_body('/', 'content-length' => 18);
ok($f->{headers}, 'cl many');
is($f->{upload}('01234many', body_split => [ 5 ], body_more => 1),
	'01234many', 'cl many - part');
is($f->{upload}('56789many', body_split => [ 5 ]), '56789many_eos',
	'cl many - part 2');
is($f->{http_end}(), 200, 'cl many - response');

$f = get_body('/', 'content-length' => 0);
ok($f->{headers}, 'cl empty');
is($f->{upload}('', body_more => 1, wait => 0.2), '', 'cl empty - part');
is($f->{upload}(''), '_eos', 'cl empty - part 2');
is($f->{http_end}(), 200, 'cl empty - response');

$f = get_body('/', 'content-length' => 10);
ok($f->{headers}, 'cl split');
is($f->{upload}('0123456789', split => [ 14 ]), '0123456789_eos', 'cl split');
is($f->{http_end}(), 200, 'cl split - response');

###############################################################################

# Simple FastCGI responder implementation.

# http://www.fastcgi.com/devkit/doc/fcgi-spec.html

sub fastcgi_read_record($) {
	my ($buf) = @_;
	my $h;

	return undef unless length $$buf;

	@{$h}{qw/ version type id clen plen /} = unpack("CCnnC", $$buf);

	$h->{content} = substr $$buf, 8, $h->{clen};
	$h->{padding} = substr $$buf, 8 + $h->{clen}, $h->{plen};

	$$buf = substr $$buf, 8 + $h->{clen} + $h->{plen};

	return $h;
}

sub fastcgi_respond($$$$) {
	my ($socket, $version, $id, $body) = @_;

	# stdout
	$socket->write(pack("CCnnCx", $version, 6, $id, length($body), 0));
	$socket->write($body);

	# close stdout
	$socket->write(pack("CCnnCx", $version, 6, $id, 0, 0));

	# end request
	$socket->write(pack("CCnnCx", $version, 3, $id, 8, 0));
	$socket->write(pack("NCxxx", 0, 0));
}

sub get_body {
	my ($url, %extra) = @_;
	my ($server, $client, $f);

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Timeout => 3,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $s = Test::Nginx::HTTP2->new();
	my $sid = exists $extra{'content-length'}
		? $s->new_stream({ headers => [
			{ name => ':method', value => 'GET' },
			{ name => ':scheme', value => 'http' },
			{ name => ':path', value => $url, },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-length',
				value => $extra{'content-length'} }],
			body_more => 1 })
		: $s->new_stream({ path => $url, body_more => 1 });

	$client = $server->accept() or return;

	log2c("(new connection $client)");

	$f->{headers} = backend_read($client);

	my $h = fastcgi_read_record(\$f->{headers});
	my $version = $h->{version};
	my $id = $h->{id};

	$f->{upload} = sub {
		my ($body, %extra) = @_;
		my $len = length($body);
		my $wait = $extra{wait};

		$s->h2_body($body, { %extra });

		$body = '';

		for (1 .. 10) {
			my $buf = backend_read($client, $wait) or return '';

			while (my $h = fastcgi_read_record(\$buf)) {

				# skip everything unless stdin
				next if $h->{type} != 5;

				$body .= $h->{content};

				# mark the end-of-stream indication
				$body .= "_eos" if $h->{clen} == 0;
			}

			last if length($body) >= $len;
		}

		return $body;
	};
	$f->{http_end} = sub {
		local $SIG{PIPE} = 'IGNORE';

		fastcgi_respond($client, $version, $id, <<EOF);
Status: 200 OK
Connection: close

OK
EOF

		$client->close;

		my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		return $frame->{headers}->{':status'};
	};
	return $f;
}

sub backend_read {
	my ($s, $timo) = @_;
	my $buf = '';

	if (IO::Select->new($s)->can_read($timo || 8)) {
		$s->sysread($buf, 16384) or return;
		log2i($buf);
	}
	return $buf;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
