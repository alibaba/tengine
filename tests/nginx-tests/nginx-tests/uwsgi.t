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

my $t = Test::Nginx->new()->has(qw/http uwsgi/)->has_daemon('uwsgi')->plan(3)
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
            uwsgi_pass 127.0.0.1:8081;
            uwsgi_param SERVER_PROTOCOL $server_protocol;
            uwsgi_param HTTP_X_BLAH "blah";
        }
    }
}

EOF

$t->write_file('uwsgi_test_app.py', <<END);

def application(env, start_response):
    start_response('200 OK', [('Content-Type','text/plain')])
    return "SEE-THIS"

END

my $uwsgihelp = `uwsgi -h`;
my @uwsgiopts = ();

if ($uwsgihelp !~ /--wsgi-file/) {
	# uwsgi has no python support, maybe plugin load is necessary
	push @uwsgiopts, '--plugin', 'python';
}

$t->run_daemon('uwsgi', '--socket', '127.0.0.1:8081', @uwsgiopts,
	'--wsgi-file', $t->testdir() . '/uwsgi_test_app.py',
	'--logto', $t->testdir() . '/uwsgi_log');

$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Can't start uwsgi";

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'uwsgi request');
unlike(http_head('/head'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get_headers('/headers'), qr/SEE-THIS/,
	'uwsgi request with many ignored headers');

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
