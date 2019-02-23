#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for log module variables.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format time_iso8601  '$uri $time_iso8601';
    log_format time_local    '$uri $time_local';
    log_format msec          '$uri $msec';
    log_format request       '$uri $status $request_length $request_time';
    log_format bytes         '$uri $bytes_sent $body_bytes_sent';
    log_format pipe          '$uri $pipe';

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /iso8601 {
            access_log %%TESTDIR%%/iso8601.log time_iso8601;
            return 200;
        }

        location /local {
            access_log %%TESTDIR%%/local.log time_local;
            return 200;
        }

        location /msec {
            access_log %%TESTDIR%%/msec.log msec;
            return 200;
        }

        location /request {
            access_log %%TESTDIR%%/request.log request;
            return 200;
        }

        location /bytes {
           access_log %%TESTDIR%%/bytes.log bytes;
           return 200 OK;
        }

        location /pipe {
            access_log %%TESTDIR%%/pipe.log pipe;
            return 200;
        }
    }
}

EOF

$t->run();

###############################################################################

http_get('/iso8601');
http_get('/local');
http_get('/msec');
http_get('/request');
my $bytes_sent = length http_get('/bytes');

# pipelined requests

http(<<EOF);
GET /pipe HTTP/1.1
Host: localhost

GET /pipe HTTP/1.1
Host: localhost
Connection: close

EOF

$t->stop();

my $log = $t->read_file('iso8601.log');
like($log, qr!/iso8601 \d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d!,
	'time_iso8601');

$log = $t->read_file('local.log');
like($log, qr!/local \d\d/[A-Z][a-z]{2}/\d{4}:\d\d:\d\d:\d\d [+-]\d{4}!,
	'time_local');

$log = $t->read_file('msec.log');
like($log, qr!/msec [\d\.]+!, 'msec');

$log = $t->read_file('request.log');
like($log, qr!/request 200 39 [\d\.]+!, 'request');

$log = $t->read_file('bytes.log');
is($log, "/bytes $bytes_sent 2\n", 'bytes sent');

$log = $t->read_file('pipe.log');
is($log, "/pipe .\n/pipe p\n", 'pipe');

###############################################################################
