#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http mirror module and it's interaction with proxy.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy mirror rewrite limit_req/);

$t->write_file_expand('nginx.conf', <<'EOF')->plan(7);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone  $uri  zone=slow:1m  rate=30r/m;
    log_format  test  $request_uri:$request_body;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            mirror /mirror;
            proxy_pass http://127.0.0.1:8081;
        }

        location /off {
            mirror /mirror/off;
            mirror_request_body off;
            proxy_pass http://127.0.0.1:8081;
        }

        location /mirror {
            internal;
            proxy_pass http://127.0.0.1:8082;
            limit_req  zone=slow burst=1;
        }

        location /mirror/off {
            internal;
            proxy_pass http://127.0.0.1:8082;
            proxy_set_header Content-Length "";
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        server_name  localhost;

        location / {
            proxy_pass http://127.0.0.1:$server_port/return204;
            access_log %%TESTDIR%%/test.log test;
            add_header X-Body $request_body;
        }

        location /return204 {
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

like(http_post('/'), qr/X-Body: 1234567890\x0d?$/m, 'mirror proxy');
like(http_post('/off'), qr/X-Body: 1234567890\x0d?$/m, 'mirror_request_body');

# delayed subrequest should not affect main request processing nor stuck itself

my $s = http_post('/delay?1', start => 1);
like(read_keepalive($s), qr/X-Body: 1234567890\x0d?$/m, 'mirror delay');

$t->todo_alerts();
$t->stop();

my $log = $t->read_file('test.log');
like($log, qr!^/:1234567890$!m, 'log - request body');
like($log, qr!^/mirror:1234567890$!m, 'log - request body in mirror');
like($log, qr!^/off:1234567890$!m, 'log - mirror_request_body off');
like($log, qr!^/mirror/off:-$!m,, 'log - mirror_request_body off in mirror');

###############################################################################

sub http_post {
	my ($url, %extra) = @_;

	http(<<EOF, %extra);
POST $url HTTP/1.0
Host: localhost
Content-Length: 10

1234567890
EOF
}

sub read_keepalive {
	my ($s) = @_;
	my $data = '';

	while (IO::Select->new($s)->can_read(3)) {
		sysread($s, my $buffer, 4096) or last;
		$data .= $buffer;
		last if $data =~ /^\x0d\x0a/ms;
	}

	log_in($data);
	return $data;
}

###############################################################################
