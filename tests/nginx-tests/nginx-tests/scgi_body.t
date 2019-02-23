#!/usr/bin/perl

# (C) Maxim Dounin

# Test for scgi backend with chunked request body.

###############################################################################

use warnings;
use strict;

use Test::More;

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
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################


like(http_get('/'), qr/X-Body: /, 'scgi no body');

like(http_get_length('/', ''), qr/X-Body: /, 'scgi empty body');
like(http_get_length('/', 'foobar'), qr/X-Body: foobar/, 'scgi body');

like(http(<<EOF), qr/X-Body: foobar/, 'scgi chunked');
GET / HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

6
foobar
0

EOF

like(http(<<EOF), qr/X-Body: /, 'scgi empty chunked');
GET / HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

0

EOF

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

		read($request->connection, $body,
			$request->env->{CONTENT_LENGTH});

		$request->connection()->print(<<EOF);
Location: http://localhost/redirect
Content-Type: text/html
X-Body: $body

SEE-THIS
EOF
	}
}

###############################################################################
