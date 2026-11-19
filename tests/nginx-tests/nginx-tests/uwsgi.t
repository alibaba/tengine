#!/usr/bin/perl

# (C) Maxim Dounin

# Test for uwsgi backend.

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

my $t = Test::Nginx->new()->has(qw/http uwsgi/)->has_daemon('uwsgi')->plan(8)
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
            uwsgi_pass 127.0.0.1:8081;
            uwsgi_param SERVER_PROTOCOL $server_protocol;
            uwsgi_param HTTP_X_BLAH "blah";
        }

        location /var {
            uwsgi_pass $arg_b;
            uwsgi_param SERVER_PROTOCOL $server_protocol;
        }
    }
}

EOF

$t->write_file('uwsgi_test_app.py', <<END);

def application(env, start_response):
    start_response('200 OK', [
       ('Content-Type', 'text/plain'),
       ('X-Forwarded-For', env.get('HTTP_X_FORWARDED_FOR', '')),
       ('X-Cookie', env.get('HTTP_COOKIE', '')),
       ('X-Foo', env.get('HTTP_FOO', ''))
    ])
    return b"SEE-THIS"

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

like(http_get('/'), qr/SEE-THIS/, 'uwsgi request');
unlike(http_head('/head'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get_headers('/headers'), qr/SEE-THIS/,
	'uwsgi request with many ignored headers');

like(http_get('/var?b=127.0.0.1:' . port(8081)), qr/SEE-THIS/,
	'uwsgi with variables');
like(http_get('/var?b=u'), qr/SEE-THIS/, 'uwsgi with variables to upstream');

my $r = http(<<EOF);
GET / HTTP/1.0
Host: localhost
X-Forwarded-For: foo
X-Forwarded-For: bar
X-Forwarded-For: bazz
Cookie: foo
Cookie: bar
Cookie: bazz
Foo: foo
Foo: bar
Foo: bazz

EOF

like($r, qr/X-Forwarded-For: foo, bar, bazz/,
	'uwsgi with multiple X-Forwarded-For headers');
like($r, qr/X-Cookie: foo; bar; bazz/,
	'uwsgi with multiple Cookie headers');
like($r, qr/X-Foo: foo, bar, bazz/,
	'uwsgi with multiple unknown headers');

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
