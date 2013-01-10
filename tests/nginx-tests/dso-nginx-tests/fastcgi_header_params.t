#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi header params.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi/)->plan(1);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass 127.0.0.1:8081;
            fastcgi_param HTTP_X_BLAH "blah";
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run();

###############################################################################

SKIP: {
skip 'unsafe', 1 unless $ENV{TEST_NGINX_UNSAFE};

local $TODO = 'not yet';

like(http_get_headers('/'), qr/SEE-THIS/,
	'fastcgi request with many ignored headers');

}

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

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html

SEE-THIS
$count
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
