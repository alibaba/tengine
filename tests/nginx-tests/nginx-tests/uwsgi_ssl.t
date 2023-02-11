#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Nginx, Inc.

# Test for uwsgi backend with SSL.

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

my $t = Test::Nginx->new()->has(qw/http uwsgi http_ssl/)
	->has_daemon('uwsgi')->has_daemon('openssl')->plan(7)
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
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_param SERVER_PROTOCOL $server_protocol;
            uwsgi_param HTTP_X_BLAH "blah";
            uwsgi_pass_request_body off;
        }

        location /var {
            uwsgi_pass suwsgi://$arg_b;
            uwsgi_param SERVER_PROTOCOL $server_protocol;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();
my $crt = "$d/uwsgi.crt";
my $key = "$d/uwsgi.key";

foreach my $name ('uwsgi') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('uwsgi_test_app.py', <<END);

def application(env, start_response):
    start_response('200 OK', [('Content-Type','text/plain')])
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
$t->run_daemon('uwsgi', @uwsgiopts,
	'--ssl-socket', '127.0.0.1:' . port(8081) . ",$crt,$key",
	'--wsgi-file', $d . '/uwsgi_test_app.py',
	'--logto', $d . '/uwsgi_log');
open STDERR, ">&", \*OLDERR;

$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start uwsgi";

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'uwsgi request');
like(http_head('/head'), qr/200 OK(?!.*SEE-THIS)/s, 'no data in HEAD');

like(http_get_headers('/headers'), qr/SEE-THIS/,
	'uwsgi request with many ignored headers');

like(http_get('/var?b=127.0.0.1:' . port(8081)), qr/SEE-THIS/,
	'uwsgi with variables');
like(http_get('/var?b=u'), qr/SEE-THIS/, 'uwsgi with variables to upstream');

like(http_post('/'), qr/SEE-THIS/, 'uwsgi post');
like(http_post_big('/'), qr/SEE-THIS/, 'uwsgi big post');

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

sub http_post {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10" . CRLF .
		CRLF .
		"1234567890";

	return http($p, %extra);
}

sub http_post_big {
	my ($url, %extra) = @_;

	my $p = "POST $url HTTP/1.0" . CRLF .
		"Host: localhost" . CRLF .
		"Content-Length: 10240" . CRLF .
		CRLF .
		("1234567890" x 1024);

	return http($p, %extra);
}

###############################################################################
