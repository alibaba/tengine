#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend with chunked request body.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

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
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param REQUEST_URI $request_uri;
            fastcgi_param CONTENT_LENGTH $content_length;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/X-Body: _eos\x0d?$/ms, 'fastcgi no body');

like(http_get_length('/', ''), qr/X-Body: _eos\x0d?$/ms, 'fastcgi empty body');
like(http_get_length('/', 'foobar'), qr/X-Body: foobar_eos\x0d?$/ms,
	'fastcgi body');

like(http_get_chunked('/', 'foobar'), qr/X-Body: foobar_eos\x0d?$/ms,
	'fastcgi chunked');
like(http_get_chunked('/', ''), qr/X-Body: _eos\x0d?$/ms,
	'fastcgi empty chunked');

###############################################################################

sub http_get_length {
	my ($url, $body) = @_;
	my $length = length $body;
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Content-Length: $length

$body
EOF
}

sub http_get_chunked {
	my ($url, $body) = @_;
	my $length = sprintf("%x", length $body);
	$body = $length ? $length . CRLF . $body . CRLF : '';
	$body .= '0' . CRLF . CRLF;
	return http(<<EOF . $body);
GET $url HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF
}

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

sub fastcgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		Test::Nginx::log_core('||', "fastcgi connection");

		$client->sysread(my $buf, 1024) or next;

		my ($version, $id);
		my $body = '';

		while (my $h = fastcgi_read_record(\$buf)) {
			$version = $h->{version};
			$id = $h->{id};

			Test::Nginx::log_core('||', "fastcgi record: "
				. " $h->{version}, $h->{type}, $h->{id}, "
				. "'$h->{content}'");

			if ($h->{type} == 5) {
				$body .= $h->{content} if $h->{clen} > 0;

				# count stdin end-of-stream
				$body .= '_eos' if $h->{clen} == 0;
			}
		}

		# respond
		fastcgi_respond($client, $version, $id, <<EOF);
Location: http://localhost/redirect
Content-Type: text/html
X-Body: $body

SEE-THIS
EOF
	}
}

###############################################################################
