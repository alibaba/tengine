#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# A rate-limited TLS response must complete without blocking other requests.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_content http_end /;

###############################################################################

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format requests $uri;
    access_log %%TESTDIR%%/requests.log requests;

    server {
        listen 127.0.0.1:8443 ssl;
        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        location = /download {
            limit_rate 16k;
            limit_rate_after 1k;
        }

        location = /probe {
            return 200 "ready\n";
        }
    }
}

EOF

$t->write_file('openssl.conf', <<'EOF');
[ req ]
distinguished_name = dn
[ dn ]
EOF

my $d = $t->testdir();
system('openssl req -x509 -newkey rsa:2048 -nodes '
	. "-config $d/openssl.conf -subj /CN=localhost/ "
	. "-out $d/localhost.crt -keyout $d/localhost.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate: $!\n";

my $payload = '0123456789abcdef' x 4096;
$t->write_file('download', $payload);
$t->plan(5)->run();

###############################################################################

my $download = http_get('/download', SSL => 1, start => 1);
my $status = eval {
	local $SIG{ALRM} = sub { die "timeout reading status line\n" };
	alarm(8);
	my $line = $download ? $download->getline() : undef;
	alarm(0);
	$line;
};
alarm(0);
diag($@) if $@;
like($status, qr/^HTTP\/1\.[01] 200\b/, 'TLS download returns 200');

my $probe = http_get('/probe', SSL => 1);
like($probe, qr/^HTTP\/1\.[01] 200\b/, 'concurrent TLS request returns 200');
is(http_content($probe), "ready\n", 'concurrent response body');

my $rest = $download ? http_end($download) : undef;
my $body = defined $status && defined $rest
	? http_content($status . $rest) : undef;
ok(defined $body && $body eq $payload, 'complete rate-limited response body');

$t->stop();
is($t->read_file('requests.log'), "/probe\n/download\n",
	'concurrent request finishes before the download');

###############################################################################
