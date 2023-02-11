#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for unbuffered request body with fastcgi backend.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi rewrite/)->plan(15);

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
        fastcgi_request_buffering off;
        fastcgi_param REQUEST_URI $request_uri;
        fastcgi_param CONTENT_LENGTH $content_length;

        location / {
            client_body_buffer_size 2k;
            fastcgi_pass 127.0.0.1:8081;
        }
        location /single {
            client_body_in_single_buffer on;
            fastcgi_pass 127.0.0.1:8081;
        }
        location /preread {
            fastcgi_pass 127.0.0.1:8082;
        }
        location /error_page {
            fastcgi_pass 127.0.0.1:8081;
            error_page 404 /404;
            fastcgi_intercept_errors on;
        }
        location /404 {
            return 200 "$request_body\n";
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/X-Body: \x0d\x0a?/ms, 'no body');

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

# interactive tests

my $s = get_body('/preread', port(8082), 10);
ok($s, 'no preread');

SKIP: {
skip 'no preread failed', 3 unless $s;

is($s->{upload}('01234'), '01234', 'no preread - body part');
is($s->{upload}('56789'), '56789', 'no preread - body part 2');

like($s->{http_end}(), qr/200 OK/, 'no preread - response');

}

$s = get_body('/preread', port(8082), 10, '01234');
ok($s, 'preread');

SKIP: {
skip 'preread failed', 3 unless $s;

is($s->{preread}, '01234', 'preread - preread');
is($s->{upload}('56789'), '56789', 'preread - body');

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
	$socket->write(pack("CCnnCx", $version, 6, $id, length($body), 8));
	$socket->write($body);
	select(undef, undef, undef, 0.1);
	$socket->write(pack("xxxxxxxx"));
	select(undef, undef, undef, 0.1);

	# write some text to stdout and stderr split over multiple network
	# packets to test if we correctly set pipe length in various places

	my $tt = "test text, just for test";

	$socket->write(pack("CCnnCx", $version, 6, $id,
		length($tt . $tt), 0) . $tt);
	select(undef, undef, undef, 0.1);
	$socket->write($tt . pack("CC", $version, 7));
	select(undef, undef, undef, 0.1);
	$socket->write(pack("nnCx", $id, length($tt), 0));
	select(undef, undef, undef, 0.1);
	$socket->write($tt);
	select(undef, undef, undef, 0.1);

	# close stdout
	$socket->write(pack("CCnnCx", $version, 6, $id, 0, 0));

	select(undef, undef, undef, 0.1);

	# end request
	$socket->write(pack("CCnnCx", $version, 3, $id, 8, 0));
	select(undef, undef, undef, 0.1);
	$socket->write(pack("NCxxx", 0, 0));
}

sub get_body {
	my ($url, $port, $length, $body) = @_;
	my ($server, $client, $s);
	my ($version, $id);

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

	$body = '';

	while (my $h = fastcgi_read_record(\$buf)) {
		$version = $h->{version};
		$id = $h->{id};

		# skip everything unless stdin
		next if $h->{type} != 5;

		$body .= $h->{content};
	}

	my $f = { preread => $body };
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

			$body = '';

			while (my $h = fastcgi_read_record(\$buf)) {

				# skip everything unless stdin
				next if $h->{type} != 5;

				$body .= $h->{content};
			}

			alarm(0);
		};
		alarm(0);
		if ($@) {
			log_in("died: $@");
			return undef;
		}

		return $body;
	};
	$f->{http_end} = sub {
		my $buf = '';

		eval {
			local $SIG{ALRM} = sub { die "timeout\n" };
			local $SIG{PIPE} = sub { die "sigpipe\n" };
			alarm(5);

			fastcgi_respond($client, $version, $id, <<EOF);
Status: 200 OK
Connection: close
X-Port: $port

OK
EOF

			$client->close;

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

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:' . port(8081), 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	my $body;

	while( $request->Accept() >= 0 ) {
		$count++;
		read(STDIN, $body, $ENV{'CONTENT_LENGTH'} || 0);

		if ($ENV{REQUEST_URI} eq '/error_page') {
			print "Status: 404 Not Found" . CRLF . CRLF;
			next;
		}

		print <<EOF;
Location: http://localhost/redirect
Content-Type: text/html
X-Body: $body

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
