#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for uwsgi backend with SSL, backend certificate verification.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl uwsgi/)
	->has_daemon('uwsgi')->has_daemon('openssl')->plan(6)
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

        location /verify {
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_ssl_name example.com;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 1.example.com.crt;
        }

        location /wildcard {
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_ssl_name foo.example.com;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 1.example.com.crt;
        }

        location /fail {
            uwsgi_pass suwsgi://127.0.0.1:8081;
            uwsgi_ssl_name no.match.example.com;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 1.example.com.crt;
        }

        location /cn {
            uwsgi_pass suwsgi://127.0.0.1:8082;
            uwsgi_ssl_name 2.example.com;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 2.example.com.crt;
        }

        location /cn/fail {
            uwsgi_pass suwsgi://127.0.0.1:8082;
            uwsgi_ssl_name bad.example.com;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 2.example.com.crt;
        }

        location /untrusted {
            uwsgi_pass suwsgi://127.0.0.1:8082;
            uwsgi_ssl_verify on;
            uwsgi_ssl_trusted_certificate 1.example.com.crt;
            uwsgi_ssl_session_reuse off;
        }
    }
}

EOF

$t->write_file('openssl.1.example.com.conf', <<EOF);
[ req ]
prompt = no
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[ req_distinguished_name ]
commonName=no.match.example.com

[ v3_req ]
subjectAltName = DNS:example.com,DNS:*.example.com
EOF

$t->write_file('openssl.2.example.com.conf', <<EOF);
[ req ]
prompt = no
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
commonName=2.example.com
EOF

my $d = $t->testdir();
my $crt1 = "$d/1.example.com.crt";
my $crt2 = "$d/2.example.com.crt";
my $key1 = "$d/1.example.com.key";
my $key2 = "$d/2.example.com.key";

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.$name.conf "
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

if ($uwsgihelp =~ /--ssl-enable-tlsv1/) {
	# uwsgi disables TLSv1 by default since 2.0.17.1
	push @uwsgiopts, '--ssl-enable-tlsv1';
}

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run_daemon('uwsgi', @uwsgiopts,
	'--ssl-socket', '127.0.0.1:' . port(8081) . ",$crt1,$key1",
	'--wsgi-file', $d . '/uwsgi_test_app.py',
	'--logto', $d . '/uwsgi_log');
$t->run_daemon('uwsgi', @uwsgiopts,
	'--ssl-socket', '127.0.0.1:' . port(8082) . ",$crt2,$key2",
	'--wsgi-file', $d . '/uwsgi_test_app.py',
	'--logto', $d . '/uwsgi_log');
open STDERR, ">&", \*OLDERR;

$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081))
	or die "Can't start uwsgi";
$t->waitforsocket('127.0.0.1:' . port(8082))
	or die "Can't start uwsgi";

###############################################################################

# subjectAltName

like(http_get('/verify'), qr/200 OK/ms, 'verify');
like(http_get('/wildcard'), qr/200 OK/ms, 'verify wildcard');
like(http_get('/fail'), qr/502 Bad/ms, 'verify fail');

# commonName

like(http_get('/cn'), qr/200 OK/ms, 'verify cn');
like(http_get('/cn/fail'), qr/502 Bad/ms, 'verify cn fail');

# untrusted

like(http_get('/untrusted'), qr/502 Bad/ms, 'untrusted');

###############################################################################
