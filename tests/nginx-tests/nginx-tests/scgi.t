#!/usr/bin/perl

# (C) Maxim Dounin

# Test for scgi backend.

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

my $t = Test::Nginx->new()->has(qw/http scgi/)->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            scgi_pass 127.0.0.1:8081;
            scgi_param SCGI 1;
            scgi_param REQUEST_URI $request_uri;
            scgi_param HTTP_X_BLAH "blah";
        }

        location /var {
            scgi_pass $arg_b;
            scgi_param SCGI 1;
            scgi_param REQUEST_URI $request_uri;
        }

    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'scgi request');
like(http_get('/redir'), qr/ 302 /, 'scgi redirect');
like(http_get('/'), qr/^3$/m, 'scgi third request');

unlike(http_head('/'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get_headers('/headers'), qr/SEE-THIS/,
	'scgi request with many ignored headers');

like(http_get('/var?b=127.0.0.1:' . port(8081)), qr/SEE-THIS/,
	'scgi with variables');
like(http_get('/var?b=u'), qr/SEE-THIS/, 'scgi with variables to upstream');

###############################################################################

sub http_get_headers {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: localhost
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header
X-Blah: ignored header

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
	my $count = 0;

	while (my $request = $scgi->accept()) {
		eval { $request->read_env(); };
		next if $@;

		$count++;

		$request->connection()->print(<<EOF);
Location: http://localhost/redirect
Content-Type: text/html

SEE-THIS
$count
EOF
	}
}

###############################################################################
