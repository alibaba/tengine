#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for scgi backend with unbuffered request body.

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

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http scgi/)->plan(5)
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
            scgi_pass 127.0.0.1:8081;
            scgi_param SCGI 1;
            scgi_param REQUEST_URI $request_uri;
            scgi_request_buffering off;
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/X-Body: 0/, 'scgi no body');

like(http_get_length('/', ''), qr/X-Body: 0/, 'scgi empty body');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.29.6');

like(http_get_length('/', 'foobar'), qr/X-Body: 6 foobar/, 'scgi body');

}

like(http_get_chunked('/', 'foobar'), qr/X-Body: 6 foobar/, 'scgi chunked');
like(http_get_chunked('/', ''), qr/X-Body: 0/, 'scgi empty chunked');

###############################################################################

sub http_get_length {
	my ($url, $body) = @_;
	my $length = length $body;
	return http(<<EOF, body => $body, sleep => 0.1);
GET $url HTTP/1.1
Host: localhost
Connection: close
Content-Length: $length

EOF
}

sub http_get_chunked {
	my ($url, $body) = @_;
	my $length = sprintf("%x", length $body);
	$body = $length ? $length . CRLF . $body . CRLF : '';
	$body .= '0' . CRLF . CRLF;
	return http(<<EOF, body => $body, sleep => 0.1);
GET $url HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

EOF
}

###############################################################################

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);
	my $body;

	while (my $request = $scgi->accept()) {
		eval { $request->read_env(); };
		next if $@;

		my $cl = $request->env->{CONTENT_LENGTH};
		read($request->connection, $body, $cl);

		$request->connection()->print(<<EOF);
Location: http://localhost/redirect
Content-Type: text/html
X-Body: $cl $body

SEE-THIS
EOF
	}
}

###############################################################################
