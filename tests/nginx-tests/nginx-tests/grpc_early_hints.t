#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for grpc backend with HTTP 103 Early Hints.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 http_v3 cryptx grpc/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        http2 on;
        early_hints 1;

        location / {
            grpc_pass grpc://127.0.0.1:8081;
        }

        location /KeepAlive {
            grpc_pass u;
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

$t->try_run('no early_hints')->plan(14);

###############################################################################

my $f = h1_grpc();
$f->{http_start}('/SayHello');
my $r = $f->{http_end}();
like($r, qr/103 Early.*Link.*200 OK.*SEE-THIS/si, 'early hints');

$f->{http_start}('/SayHello');
$r = $f->{http_end}(only => 1);
like($r, qr/502 Bad Gateway/, 'early hints only');

$f = undef;

# HTTP/2

$f = h2_grpc();
$f->{http_start}('/SayHello');
$f->{data}('Hello');

my $frames = $f->{http_end}();
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

my $frame = shift @$frames;
is($frame->{headers}{':status'}, 103, 'h2 early hints');
ok($frame->{headers}{'link'}, 'h2 early header');

$frame = shift @$frames;
is($frame->{headers}{':status'}, 200, 'h2 header');

$frame = shift @$frames;
is($frame->{type}, 'DATA', 'h2 data');

$frame = shift @$frames;
is($frame->{headers}{'grpc-message'}, '', 'h2 trailer');

$f = undef;

# HTTP/3

$f = h3_grpc();
$f->{http_start}('/SayHello');
$f->{data}('Hello');

$frames = $f->{http_end}();
@$frames = grep { $_->{type} =~ "HEADERS|DATA" } @$frames;

$frame = shift @$frames;
is($frame->{headers}{':status'}, 103, 'h3 early hints');
ok($frame->{headers}{'link'}, 'h3 early header');

$frame = shift @$frames;
is($frame->{headers}{':status'}, 200, 'h3 header');

$frame = shift @$frames;
is($frame->{type}, 'DATA', 'h3 data');

$frame = shift @$frames;
is($frame->{headers}{'grpc-message'}, '', 'h3 trailer');

$f = undef;

# upstream keepalive

$f = h2_grpc();

$f->{http_start}('/KeepAlive');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok(my $c = $frame->{headers}{'x-connection'}, 'keepalive - connection');

$f->{http_start}('/KeepAlive', reuse => 1);
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{'x-connection'}, $c, 'keepalive - connection reuse');

###############################################################################

sub h1_grpc {
	my ($server, $client, $f, $s, $c, $sid);

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	$f->{http_start} = sub {
		my ($uri) = @_;
		$s = http(<<EOF, start => 1);
GET $uri HTTP/1.1
Host: localhost
Connection: close, te
TE: trailers

EOF

		if (IO::Select->new($server)->can_read(5)) {
			$client = $server->accept();

		} else {
			log_in("timeout");
			return undef;
		}

		log2c("(new connection $client)");

		$client->sysread(my $buf, 24) == 24 or return; # preface

		$c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or return;

		my $frames = $c->read(all => [{ fin => 4 }]);

		$c->h2_settings(0);
		$c->h2_settings(1);

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{http_end} = sub {
		my (%extra) = @_;
		my $body_more = 1 unless $extra{only};
		$c->new_stream({ body_more => $body_more, headers => [
			{ name => ':status', value => '103' },
			{ name => 'link', value => 'foo', mode => 1 },
		]}, $sid);

		return http('', socket => $s) if $extra{only};

		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc' }
		]}, $sid);
		$c->h2_body('SEE-THIS', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0', mode => 2 },
			{ name => 'grpc-message', value => '', mode => 2 },
		]}, $sid);

		return http('', socket => $s);
	};
	return $f;
}

sub h2_grpc {
	my ($server, $client, $f, $s, $c, $sid);
	my $n = 0;

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	$f->{http_start} = sub {
		my ($uri, %extra) = @_;
		$s = Test::Nginx::HTTP2->new();
		my $csid = $s->new_stream({ body_more => 1, headers => [
			{ name => ':method', value => 'POST', mode => 0 },
			{ name => ':scheme', value => 'http', mode => 0 },
			{ name => ':path', value => $uri, },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-type', value => 'application/grpc' },
			{ name => 'te', value => 'trailers', mode => 2 }]});

		if (!$extra{reuse}) {
			if (IO::Select->new($server)->can_read(5)) {
				$client = $server->accept();

			} else {
				log_in("timeout");
				# connection could be unexpectedly reused
				goto reused if $client;
				return undef;
			}

			log2c("(new connection $client)");
			$n++;

			$client->sysread(my $buf, 24) == 24 or return; # preface

			$c = Test::Nginx::HTTP2->new(1, socket => $client,
				pure => 1, preface => "") or return;

			$c->h2_settings(0);
			$c->h2_settings(1);
		}

		my $frames = $c->read(all => [{ fin => 4 }]);

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{data} = sub {
		my ($body) = @_;
		$s->h2_body($body);
		return $c->read(all => [{ sid => $sid,
			length => length($body) }]);
	};
	$f->{http_end} = sub {
		my (%extra) = @_;
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '103' },
			{ name => 'link', value => 'foo', mode => 1 },
			{ name => 'x-connection', value => $n, mode => 2 },
		]}, $sid);
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc' }
		]}, $sid);
		$c->h2_body('SEE-THIS', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0', mode => 2 },
			{ name => 'grpc-message', value => '', mode => 2 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	return $f;
}

sub h3_grpc {
	my ($server, $client, $f, $s, $c, $sid, $csid);

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	$f->{http_start} = sub {
		my ($uri) = @_;
		$s = Test::Nginx::HTTP3->new();
		$csid = $s->new_stream({ body_more => 1, headers => [
			{ name => ':method', value => 'POST', mode => 0 },
			{ name => ':scheme', value => 'http', mode => 0 },
			{ name => ':path', value => $uri, },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-type', value => 'application/grpc' },
			{ name => 'te', value => 'trailers' }]});

		if (IO::Select->new($server)->can_read(5)) {
			$client = $server->accept();

		} else {
			log_in("timeout");
			return undef;
		}

		log2c("(new connection $client)");

		$client->sysread(my $buf, 24) == 24 or return; # preface

		$c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or return;

		my $frames = $c->read(all => [{ fin => 4 }]);

		$c->h2_settings(0);
		$c->h2_settings(1);

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{data} = sub {
		my ($body) = @_;
		$s->h3_body($body, $csid);
		return $c->read(all => [{ sid => $sid,
			length => length($body) }]);
	};
	$f->{http_end} = sub {
		my (%extra) = @_;
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '103' },
			{ name => 'link', value => 'foo', mode => 1 },
		]}, $sid);
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc' }
		]}, $sid);
		$c->h2_body('SEE-THIS', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0', mode => 2 },
			{ name => 'grpc-message', value => '', mode => 2 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	return $f;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
