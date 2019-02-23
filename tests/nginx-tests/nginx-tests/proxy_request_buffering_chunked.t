#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for unbuffered request body, chunked transfer-encoding.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/)->plan(22);

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
        proxy_http_version 1.1;

        location / {
            client_body_buffer_size 2k;
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8081;
        }
        location /small {
            client_body_in_file_only on;
            proxy_pass http://127.0.0.1:8080/;
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

        location / {
            proxy_pass http://127.0.0.1:8080/discard;
        }
        location /404 { }
    }
}

EOF

$t->run();

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

my $s = get_body('/preread', 8082);
ok($s, 'no preread');

SKIP: {
skip 'no preread failed', 3 unless $s;

is($s->{upload}('01234'), '5' . CRLF . '01234' . CRLF,
	'no preread - body part');
is($s->{upload}('56789', last => 1),
	'5' . CRLF . '56789' . CRLF . '0' . CRLF . CRLF,
	'no preread - body part 2');

like($s->{http_end}(), qr/200 OK/, 'no preread - response');

}

$s = get_body('/preread', 8082, '01234');
ok($s, 'preread');

SKIP: {
skip 'preread failed', 3 unless $s;

is($s->{preread}, '5' . CRLF . '01234' . CRLF, 'preread - preread');
is($s->{upload}('56789', last => 1),
	'5' . CRLF . '56789' . CRLF . '0' . CRLF . CRLF, 'preread - body');

like($s->{http_end}(), qr/200 OK/, 'preread - response');

}

$s = get_body('/preread', 8082, '01234', many => 1);
ok($s, 'chunks');

SKIP: {
skip 'chunks failed', 3 unless $s;

is($s->{preread}, '9' . CRLF . '01234many' . CRLF, 'chunks - preread');
is($s->{upload}('56789', many => 1, last => 1),
	'9' . CRLF . '56789many' . CRLF . '0' . CRLF . CRLF, 'chunks - body');

like($s->{http_end}(), qr/200 OK/, 'chunks - response');

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
	my ($server, $client, $s);
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

		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	$client->sysread(my $buf, 1024);
	$buf =~ s/.*?\x0d\x0a?\x0d\x0a?(.*)/$1/ms;

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

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(5);

			$s->write($buf);
			$client->sysread($buf, 1024);

			alarm(0);
		};
		alarm(0);
		if ($@) {
			log_in("died: $@");
			return undef;
		}

		return $buf;
	};
	$f->{http_end} = sub {
		my $buf = '';

		$client->write(<<EOF);
HTTP/1.1 200 OK
Connection: close
X-Port: $port

OK
EOF

		$client->close;

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(5);

			$s->sysread($buf, 1024);
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

###############################################################################
