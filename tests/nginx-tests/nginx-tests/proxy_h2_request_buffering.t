#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for unbuffered request body to HTTP/2 backend.

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

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy rewrite/);

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

        client_header_buffer_size 1k;
        proxy_request_buffering off;
        proxy_http_version 2;

        location / {
            client_body_buffer_size 2k;
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8081;
        }
        location /small {
            client_body_in_file_only on;
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8081/;
        }
        location /single {
            client_body_in_single_buffer on;
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8081;
        }
        location /discard {
            return 200 "TEST\n";
        }
        location /preread {
            proxy_pass http://127.0.0.1:8082/;
        }
        location /error_page {
            proxy_pass http://127.0.0.1:8081/404;
            error_page 404 /404;
            proxy_intercept_errors on;
        }
        location /404 {
            return 200 "$request_body\n";
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        http2 on;

        location / {
            proxy_pass http://127.0.0.1:8080/discard;
        }
        location /404 { }
    }
}

EOF

$t->try_run('no proxy_http_version 2')->plan(26);

###############################################################################

unlike(http_get('/'), qr/X-Body:/ms, 'no body');

like(http_get_body('/', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'body');

like(http_get_body('/', '0123456789' x 128),
	qr/X-Body: (0123456789){128}\x0d?$/ms, 'body in two buffers');

like(http_get_body('/single', '0123456789' x 128),
	qr/X-Body: (0123456789){128}\x0d?$/ms, 'body in single buffer');

like(http_get_body('/error_page', '0123456789'),
	qr/^0123456789$/m, 'body in error page');

# pipelined requests

like(http_get_body('/', '0123456789', '0123456789' x 128, '0123456789' x 512,
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'body pipelined');
like(http_get_body('/', '0123456789' x 128, '0123456789' x 512, '0123456789',
	'foobar'), qr/X-Body: foobar\x0d?$/ms, 'body pipelined 2');

like(http_get_body('/discard', '0123456789', '0123456789' x 128,
	'0123456789' x 512, 'foobar'), qr/(TEST.*){4}/ms,
	'body discard');
like(http_get_body('/discard', '0123456789' x 128, '0123456789' x 512,
	'0123456789', 'foobar'), qr/(TEST.*){4}/ms,
	'body discard 2');

# proxy with file only is disabled in unbuffered mode

like(http_get_body('/small', '0123456789'),
	qr/X-Body: 0123456789\x0d?$/ms, 'small body in file only');

# interactive tests

my $s = get_body('/preread', port(8082));
ok($s, 'no preread');

SKIP: {
skip 'no preread failed', 3 unless $s;

is($s->{upload}('01234'), '01234', 'no preread - body part');
is($s->{upload}('56789', last => 1), '56789', 'no preread - body part 2');
like($s->{http_end}(), qr/200 OK/, 'no preread - response');

}

$s = get_body('/preread', port(8082), '01234');
ok($s, 'preread');

SKIP: {
skip 'preread failed', 3 unless $s;

is($s->{preread}, '01234', 'preread - preread');
is($s->{upload}('56789', last => 1), '56789', 'preread - body');
like($s->{http_end}(), qr/200 OK/, 'preread - response');

}

$s = get_body('/preread', port(8082), '01234', many => 1);
ok($s, 'many');

SKIP: {
skip 'many failed', 3 unless $s;

is($s->{preread}, '01234many', 'many - preread');
is($s->{upload}('56789', many => 1, last => 1), '56789many', 'many - body');
like($s->{http_end}(), qr/200 OK/, 'many - response');

}

$s = get_body('/preread', port(8082));
ok($s, 'last');

SKIP: {
skip 'last failed', 3 unless $s;

is($s->{upload}('01234'), '01234', 'last - body');
is($s->{upload}('', last => 1), '', 'last - special buffer');
like($s->{http_end}(), qr/200 OK/, 'last - response');

}

###############################################################################

sub http_get_body {
	my $uri = shift;
	my $last = pop;
	return http( join '', (map {
		my $body = $_;
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $body) . CRLF
		. $body . CRLF
		. "0" . CRLF . CRLF
	} @_),
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF
		. sprintf("%x", length $last) . CRLF
		. $last . CRLF
		. "0" . CRLF . CRLF
	);
}

sub get_body {
	my ($url, $port, $body, %extra) = @_;
	my ($server, $client, $s, $c, $sid);
	my ($last, $many) = (0, 0);

	$last = $extra{last} if defined $extra{last};
	$many = $extra{many} if defined $extra{many};

	$server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $r = <<EOF;
GET $url HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF

	if (defined $body) {
		$r .= sprintf("%x", length $body) . CRLF;
		$r .= $body . CRLF;
	}
	if (defined $body && $many) {
		$r .= sprintf("%x", length 'many') . CRLF;
		$r .= 'many' . CRLF;
	}
	if ($last) {
		$r .= "0" . CRLF . CRLF;
	}

	$s = http($r, start => 1);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(5);

		$client = $server->accept();

		log2c("(new connection $client)");

		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	$client->sysread(my $buf, 24) == 24 or next; # preface
	log2i($buf);

	$c = Test::Nginx::HTTP2->new(1, socket => $client,
		pure => 1, preface => "") or next;

	$c->h2_settings(0);
	$c->h2_settings(1);

	my $frames = $c->read(all => [{ type => 'DATA' }], wait => 0.1);
	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	$sid = $frame->{sid};
	($frame) = grep { $_->{type} eq "DATA" } @$frames;
	$buf = $frame->{data};

	my $f = { preread => $buf };
	$f->{upload} = sub {
		my ($body, %extra) = @_;
		my ($last, $many) = (0, 0);

		$last = $extra{last} if defined $extra{last};
		$many = $extra{many} if defined $extra{many};

		my $buf = sprintf("%x", length $body) . CRLF;
		$buf .= $body . CRLF;
		if ($many) {
			$buf .= sprintf("%x", length 'many') . CRLF;
			$buf .= 'many' . CRLF;
		}
		if ($last) {
			$buf .= "0" . CRLF . CRLF;
		}

		http($buf, socket => $s, start => 1);

		my $length = length($body . ($many ? 'many' : ''));
		$frames = $c->read(all => [{ sid => $sid, length => $length }]);
		($frame) = grep { $_->{type} eq "DATA" } @$frames;
		return $frame->{data};
	};
	$f->{http_end} = sub {
		my $buf = '';

		$c->new_stream({ headers => [
			{ name => ':status', value => '200' }
		]}, $sid);

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(5);

			$s->sysread($buf, 1024);
			log_in($buf);

			$s->close();

			alarm(0);
		};
		alarm(0);
		if ($@) {
			log_in("died: $@");
			return undef;
		}

		return $buf;
	};
	return $f;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
