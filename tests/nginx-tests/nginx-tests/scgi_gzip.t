#!/usr/bin/perl

# (C) Maxim Dounin

# Test for scgi backend and gzip.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http scgi gzip/)->plan(1)
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
            gzip on;
            scgi_pass 127.0.0.1:8081;
            scgi_param SCGI 1;
            scgi_param REQUEST_URI $request_uri;
            scgi_param HTTP_X_BLAH "blah";
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run();

###############################################################################

like(http_gzip_request('/'), qr/Content-Encoding: gzip/, 'scgi request');

###############################################################################

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);

	while (my $request = $scgi->accept()) {
		$request->read_env();

		$request->connection()->print(<<EOF);
Content-Type: text/html

SEE-THIS-1234567890-1234567890
EOF
	}
}

###############################################################################
