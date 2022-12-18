#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Test for uwsgi backend with request body.

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

my $t = Test::Nginx->new()->has(qw/http rewrite uwsgi/)
	->has_daemon('uwsgi')->plan(5)
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

        set $variable $content_length;

        location / {
            uwsgi_pass 127.0.0.1:8081;
            uwsgi_param CONTENT_LENGTH $content_length if_not_empty;
        }
    }
}

EOF

$t->write_file('uwsgi_test_app.py', <<END);

def application(env, start_response):
    start_response('200 OK', [('Content-Type','text/plain')])
    if "CONTENT_LENGTH" not in env:
        return b"SEE-THIS"
    cl = int(env.get('CONTENT_LENGTH'))
    rb = env.get('wsgi.input').read(cl)
    return b"cl=%d '%s'" % (cl, rb)

END

my $uwsgihelp = `uwsgi -h`;
my @uwsgiopts = ();

if ($uwsgihelp !~ /--wsgi-file/) {
	# uwsgi has no python support, maybe plugin load is necessary
	push @uwsgiopts, '--plugin', 'python';
	push @uwsgiopts, '--plugin', 'python3';
}

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run_daemon('uwsgi', '--socket', '127.0.0.1:' . port(8081), @uwsgiopts,
	'--wsgi-file', $t->testdir() . '/uwsgi_test_app.py',
	'--logto', $t->testdir() . '/uwsgi_log');
open STDERR, ">&", \*OLDERR;

$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start uwsgi";

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'uwsgi no body');

like(http_get_length('/', 'foobar'), qr/cl=6 'foobar'/, 'uwsgi body');
like(http_get_length('/', ''), qr/cl=0 ''/, 'uwsgi empty body');

# rewrite set is used to cache $content_length early

like(http_get_chunked('/', 'foobar'), qr/cl=6 'foobar'/, 'uwsgi chunked');
like(http_get_chunked('/', ''), qr/cl=0 ''/, 'uwsgi empty chunked');

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
	return http(<<EOF);
GET $url HTTP/1.1
Host: localhost
Connection: close
Transfer-Encoding: chunked

$length
$body
0

EOF
}

###############################################################################
