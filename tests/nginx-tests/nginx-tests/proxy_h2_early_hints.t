#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/2 backend with Early Hints.

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

        early_hints 1;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 2;

            location /off/ {
                proxy_pass http://127.0.0.1:8081/;
                early_hints 0;
            }
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(3);

###############################################################################

like(get('/'), qr/103 Early.*Link.*200 OK.*SEE-THIS/si, 'early hints');
like(get('/only'), qr/502 Bad Gateway/s, 'early hints only');
unlike(get('/off/'), qr/103 Early/, 'early hints off');

###############################################################################

sub get {
	my ($uri) = @_;
	http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close

EOF
}

sub http_daemon {
	my $client;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while ($client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		my $frames = $c->read(all => [{ fin => 4 }]);
		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		my $sid = $frame->{sid};
		my $uri = $frame->{headers}{':path'};

		if ($uri eq '/') {

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '103' },
				{ name => 'link', value => 'foo' },
			]}, $sid);
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS');

		} elsif ($uri eq '/only') {

			$c->new_stream({ headers => [
				{ name => ':status', value => '103' },
				{ name => 'link', value => 'foo' },
			]}, $sid);
		}
	}
}

###############################################################################
