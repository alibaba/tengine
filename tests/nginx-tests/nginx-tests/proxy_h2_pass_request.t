#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy_pass_request_headers, proxy_pass_request_body directives.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

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

        proxy_http_version 2;
        proxy_pass_request_headers off;

        location / {
            proxy_pass http://127.0.0.1:8081;
        }

        location /body {
            proxy_pass http://127.0.0.1:8081;
            proxy_pass_request_headers on;
            proxy_pass_request_body off;
        }

        location /both {
            proxy_pass http://127.0.0.1:8081;
            proxy_pass_request_headers off;
            proxy_pass_request_body off;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(4);

###############################################################################

like(get('/', 'foo', 'bar'), qr/Header: none.*Body: bar/si, 'no headers');
like(get('/body', 'foo', 'bar'), qr/Header: foo.*Body: none/si, 'no body');
like(get('/both', 'foo', 'bar'), qr/Header: none.*Body: none/si, 'both');

like(many('/body', 'foo', '22'), qr/( foo){22}/, 'many headers');

###############################################################################

sub many{
	my ($uri, $header, $count) = @_;
	$header = ("X-Header: " . $header . CRLF) x $count;
	http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
$header

EOF
}

sub get {
	my ($uri, $header, $body) = @_;
	my $cl = length("$body");

	http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
X-Header: $header
Content-Length: $cl

$body
EOF
}

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		my $frames = $c->read(all => [{ fin => 4 }]);
		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		my $sid = $frame->{sid};

		my $header = $frame->{headers}{'x-header'} || 'none';
		$header = ref $header ? join ' ', @$header : $header;
		if ($frame->{flags} == 4) {
			$frames = $c->read(all => [{ sid=> $sid, fin => 1 }]);
			($frame) = grep { $_->{type} eq "DATA" } @$frames;
		}
		my $body = $frame->{flags} == 1 && $frame->{data} || 'none';

		$c->new_stream({ headers => [
			{ name => ':status', value => '200' },
			{ name => 'x-header', value => $header, mode => 2 },
			{ name => 'x-body', value => $body, mode => 2 },
		]}, $sid);
	}
}

###############################################################################
