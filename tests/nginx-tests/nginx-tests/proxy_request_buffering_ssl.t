#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for unbuffered request body to ssl backend.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy rewrite/)
	->has_daemon('openssl')->plan(18);

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

        location / {
            client_body_buffer_size 2k;
            add_header X-Body "$request_body";
            proxy_pass https://127.0.0.1:8081;
        }
        location /single {
            client_body_in_single_buffer on;
            add_header X-Body "$request_body";
            proxy_pass https://127.0.0.1:8081;
        }
        location /discard {
            return 200 "TEST\n";
        }
        location /preread {
            proxy_pass https://127.0.0.1:8081;
        }
        location /error_page {
            proxy_pass https://127.0.0.1:8081/404;
            error_page 404 /404;
            proxy_intercept_errors on;
        }
        location /404 {
            return 200 "$request_body\n";
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location /preread {
            client_body_buffer_size 2k;
            add_header X-Body "$request_body";
            proxy_pass http://127.0.0.1:8082/;
            proxy_request_buffering off;
        }

        location / {
            proxy_pass http://127.0.0.1:8080/discard;
        }
        location /404 { }
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

# interactive tests

my $s = get_body('/preread', port(8082), 10);
ok($s, 'no preread');

SKIP: {
skip 'no preread failed', 3 unless $s;

is($s->{upload}('01234'), '01234', 'no preread - body part');
is($s->{upload}('56789'), '56789', 'no preread - body part 2');

like($s->{http_end}(), qr/200 OK/, 'no preread - response');

}

$s = get_body('/preread', port(8082), 15, '01234');
ok($s, 'preread');

SKIP: {
skip 'preread failed', 3 unless $s;

is($s->{preread}, '01234', 'preread - preread');
is($s->{upload}('56789'), '56789', 'preread - body part');
is($s->{upload}('abcde'), 'abcde', 'preread - body part 2');

like($s->{http_end}(), qr/200 OK/, 'preread - response');

}

###############################################################################

sub http_get_body {
	my $uri = shift;
	my $last = pop;
	return http( join '', (map {
		my $body = $_;
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Content-Length: " . (length $body) . CRLF . CRLF
		. $body
	} @_),
		"GET $uri HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Content-Length: " . (length $last) . CRLF . CRLF
		. $last
	);
}

sub get_body {
	my ($url, $port, $length, $body) = @_;
	my ($server, $client, $s);

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
Content-Length: $length

EOF

	if (defined $body) {
		$r .= $body;
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

	$client->sysread(my $buf, 1024);
	log2i($buf);

	$buf =~ s/.*?\x0d\x0a?\x0d\x0a?(.*)/$1/ms;

	my $f = { preread => $buf };
	$f->{upload} = sub {
		my $buf = shift;

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(5);

			log_out($buf);
			$s->write($buf);

			$client->sysread($buf, 1024);
			log2i($buf);

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
			log_in($buf);

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
