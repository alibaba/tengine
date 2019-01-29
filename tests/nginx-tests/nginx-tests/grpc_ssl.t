#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for grpc backend with ssl.

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

my $t = Test::Nginx->new()->has(qw/http rewrite http_v2 grpc/)
	->has(qw/upstream_keepalive http_ssl/);

$t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;
plan(skip_all => 'OpenSSL too old') unless defined $1 and $1 ge '1.0.2';

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
        listen       127.0.0.1:8081 http2 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        ssl_verify_client optional;
        ssl_client_certificate client.crt;

        http2_max_field_size 128k;
        http2_max_header_size 128k;
        http2_body_preread_size 128k;

        location / {
            grpc_pass 127.0.0.1:8082;
            add_header X-Connection $connection;
        }
    }

    server {
        listen       127.0.0.1:8080 http2;
        server_name  localhost;

        http2_max_field_size 128k;
        http2_max_header_size 128k;
        http2_body_preread_size 128k;

        location / {
            grpc_pass grpcs://127.0.0.1:8081;
            grpc_ssl_name localhost;
            grpc_ssl_verify on;
            grpc_ssl_trusted_certificate localhost.crt;

            grpc_ssl_certificate client.crt;
            grpc_ssl_certificate_key client.key;
            grpc_ssl_password_file password;

            if ($arg_if) {
                # nothing
            }

            limit_except GET {
                # nothing
            }
        }

        location /KeepAlive {
            grpc_pass grpcs://u;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
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

foreach my $name ('client') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 1024 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

sleep 1 if $^O eq 'MSWin32';

$t->write_file('password', 'client');

$t->try_run('no grpc')->plan(33);

###############################################################################

my $p = port(8082);
my $f = grpc();

my $frames = $f->{http_start}('/SayHello');
my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'request - HEADERS flags');
ok((my $sid = $frame->{sid}) % 2, 'request - HEADERS sid odd');
is($frame->{headers}{':method'}, 'POST', 'request - method');
is($frame->{headers}{':scheme'}, 'http', 'request - scheme');
is($frame->{headers}{':path'}, '/SayHello', 'request - path');
is($frame->{headers}{':authority'}, "127.0.0.1:$p", 'request - authority');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'request - content type');
is($frame->{headers}{te}, 'trailers', 'request - te');

$frames = $f->{data}('Hello');
($frame) = grep { $_->{type} eq "SETTINGS" } @$frames;
is($frame->{flags}, 1, 'request - SETTINGS ack');
is($frame->{sid}, 0, 'request - SETTINGS sid');
is($frame->{length}, 0, 'request - SETTINGS length');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello', 'request - DATA');
is($frame->{length}, 5, 'request - DATA length');
is($frame->{flags}, 1, 'request - DATA flags');
is($frame->{sid}, $sid, 'request - DATA sid match');

$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 4, 'response - HEADERS flags');
is($frame->{sid}, 1, 'response - HEADERS sid');
is($frame->{headers}{':status'}, '200', 'response - status');
is($frame->{headers}{'content-type'}, 'application/grpc',
	'response - content type');
ok($frame->{headers}{server}, 'response - server');
ok($frame->{headers}{date}, 'response - date');
ok(my $c = $frame->{headers}{'x-connection'}, 'response - connection');

($frame) = grep { $_->{type} eq "DATA" } @$frames;
is($frame->{data}, 'Hello world', 'response - DATA');
is($frame->{length}, 11, 'response - DATA length');
is($frame->{flags}, 0, 'response - DATA flags');
is($frame->{sid}, 1, 'response - DATA sid');

(undef, $frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{flags}, 5, 'response - trailers flags');
is($frame->{sid}, 1, 'response - trailers sid');
is($frame->{headers}{'grpc-message'}, '', 'response - trailers message');
is($frame->{headers}{'grpc-status'}, '0', 'response - trailers status');

# next request is on a new backend connection, no sid incremented

$f->{http_start}('/SayHello');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
cmp_ok($frame->{headers}{'x-connection'}, '>', $c, 'response 2 - connection');

# upstream keepalive

$f->{http_start}('/KeepAlive');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
ok($c = $frame->{headers}{'x-connection'}, 'keepalive - connection');

TODO: {
local $TODO = 'not yet' if $^O eq 'MSWin32';

$f->{http_start}('/KeepAlive');
$f->{data}('Hello');
$frames = $f->{http_end}();
($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}{'x-connection'}, $c, 'keepalive - connection reuse');

}

###############################################################################

sub grpc {
	my ($server, $client, $f, $s, $c, $sid, $uri);

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $p,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	$f->{http_start} = sub {
		($uri, my %extra) = @_;
		my $body_more = 1 if $uri !~ /LongHeader/;
		$s = Test::Nginx::HTTP2->new() if !defined $s;
		$s->new_stream({ body_more => $body_more, headers => [
			{ name => ':method', value => 'POST', mode => 0 },
			{ name => ':scheme', value => 'http', mode => 0 },
			{ name => ':path', value => $uri, },
			{ name => ':authority', value => 'localhost' },
			{ name => 'content-type', value => 'application/grpc' },
			{ name => 'te', value => 'trailers', mode => 2 }]});

		if (!$extra{reuse}) {
			eval {
				local $SIG{ALRM} = sub { die "timeout\n" };
				alarm(5);

				$client = $server->accept() or return;

				alarm(0);
			};
			alarm(0);
			if ($@) {
				log_in("died: $@");
				return undef;
			}

			log2c("(new connection $client)");

			$client->sysread(my $buf, 24) == 24 or return; # preface

			$c = Test::Nginx::HTTP2->new(1, socket => $client,
				pure => 1, preface => "") or return;
		}

		my $frames = $c->read(all => [{ fin => 4 }]);

		if (!$extra{reuse}) {
			$c->h2_settings(0);
			$c->h2_settings(1);
		}

		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		$sid = $frame->{sid};
		return $frames;
	};
	$f->{data} = sub {
		my ($body, %extra) = @_;
		$s->h2_body($body, { %extra });
		return $c->read(all => [{ sid => $sid,
			length => length($body) }]);
	};
	$f->{http_end} = sub {
		$c->new_stream({ body_more => 1, headers => [
			{ name => ':status', value => '200', mode => 0 },
			{ name => 'content-type', value => 'application/grpc',
				mode => 1, huff => 1 },
		]}, $sid);
		$c->h2_body('Hello world', { body_more => 1 });
		$c->new_stream({ headers => [
			{ name => 'grpc-status', value => '0',
				mode => 2, huff => 1 },
			{ name => 'grpc-message', value => '',
				mode => 2, huff => 1 },
		]}, $sid);

		return $s->read(all => [{ fin => 1 }]);
	};
	return $f;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
