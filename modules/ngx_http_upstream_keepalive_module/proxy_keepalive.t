#!/usr/bin/perl

# (C) Maxim Dounin
# (C) cfsego

# Tests for proxy with keepalive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket::INET;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy ssi rewrite/)
	->plan(242)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

worker_processes 1;

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $server_name:$server_port $dyn {
       localhost:8080 1;
       default 0;
    }

    upstream backend {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    upstream backend1 {
        server 127.0.0.1:8081;
        keepalive 1 slice_key=$host slice_conn=1;
    }

    upstream backend2 {
        server 127.0.0.1:8081;
        keepalive 1 slice_key=$server_name:$server_port slice_dyn=$dyn;
    }

    upstream backend3 {
        server 127.0.0.1:8081;
        keepalive 1 slice_key=$host slice_conn=1 slice_poolsize=0;
    }

    upstream backend4 {
        server 127.0.0.1:8081 max_fails=0;
        keepalive 1 slice_key=$uri slice_conn=1 slice_keylen=7;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_read_timeout 2s;
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        location / {
            proxy_pass http://backend;
        }

        location /unbuffered/ {
            proxy_pass http://backend;
            proxy_buffering off;
        }

        location /inmemory/ {
            ssi on;
            rewrite ^ /ssi.html break;
        }

        location /ups1/ {
            proxy_pass http://backend1/;
        }

        location /ups1/unbuffered/ {
            proxy_pass http://backend1/;
            proxy_buffering off;
        }

        location /ups1/inmemory/ {
            ssi on;
            rewrite ^ /ssi_ups1.html break;
        }

        location /ups2/ {
            proxy_pass http://backend2/;
        }

        location /ups2/unbuffered/ {
            proxy_pass http://backend2/;
            proxy_buffering off;
        }

        location /ups2/inmemory/ {
            ssi on;
            rewrite ^ /ssi_ups2.html break;
        }

        location /ups3/ {
            proxy_pass http://backend3/;
        }

        location /ups3/unbuffered/ {
            proxy_pass http://backend3/;
            proxy_buffering off;
        }

        location /ups3/inmemory/ {
            ssi on;
            rewrite ^ /ssi_ups3.html break;
        }

        location /ups4/ {
            rewrite /ups4(/.*)$ $1 break;
            proxy_pass http://backend4;
        }

        location /ups4/buffered/ {
            rewrite /ups4/buffered(/.*)$ $1 break;
            proxy_pass http://backend4;
            proxy_buffering off;
        }

        location /ups4/unbuffered/ {
            rewrite /ups4/unbuffered(/.*)$ $1 break;
            proxy_pass http://backend4;
            proxy_buffering off;
        }

        location /ups4/inmemory/ {
            ssi on;
            rewrite ^ /ssi_ups4.html break;
        }
    }
}

EOF

$t->write_file('ssi.html',
	'<!--#include virtual="/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->write_file('ssi_ups1.html',
	'<!--#include virtual="/ups1/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->write_file('ssi_ups2.html',
	'<!--#include virtual="/ups2/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->write_file('ssi_ups3.html',
	'<!--#include virtual="/ups3/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->write_file('ssi_ups4.html',
	'<!--#include virtual="/ups4/include$request_uri" set="x" -->' .
	'set: <!--#echo var="x" -->');

$t->run_daemon(\&http_daemon);
$t->run();

$t->waitforsocket('127.0.0.1:8081')
	or die "Can't start test backend";

###############################################################################

# There are 3 mostly independend modes of upstream operation:
#
# 1. Buffered, i.e. normal mode with "proxy_buffering on;"
# 2. Unbuffered, i.e. "proxy_buffering off;".
# 3. In memory, i.e. ssi <!--#include ... set -->
#
# These all should be tested.

my ($r, $n);

# buffered

like($r = http_get('/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');

like($r = http_get('/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');

like($r = http_get('/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');

like($r = http_get('/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');

like($r = http_head('/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');

like($r = http_get('/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/empty2'), qr/X-Connection: $n/, 'buffered empty 2');

like($r = http_get('/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');

like($r = http_get('/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');

like($r = http_get('/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');

like($r = http_get('/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');

like($r = http_get('/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');

like($r = http_get('/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/empty2'), qr/X-Connection: $n/,
	'unbuffered empty 2');

like($r = http_head('/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');

like($r = http_get('/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');

like($r = http_get('/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/unbuffered/304len2'), qr/X-Connection: $n/,
	'unbuffered 304 with length 2');

# in memory

like($r = http_get('/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');

like($r = http_get('/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/empty2'), qr/200 OK/, 'inmemory empty 2');

like($r = http_get('/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');

like($r = http_get('/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');

like(http_get('/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');

# closed connection tests

like(http_get('/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

# check for errors, shouldn't be any

like(`grep -F '[alert]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no alerts');
like(`grep -F '[error]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no errors');

#############################################################################

# buffered

like($r = http_get('/ups1/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');

like($r = http_get('/ups1/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');

like($r = http_get('/ups1/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');

like($r = http_get('/ups1/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');

like($r = http_head('/ups1/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups1/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');

like($r = http_get('/ups1/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/empty2'), qr/X-Connection: $n/, 'buffered empty 2');

like($r = http_get('/ups1/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');

like($r = http_get('/ups1/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/ups1/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');

like($r = http_get('/ups1/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');

like($r = http_get('/ups1/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');

like($r = http_get('/ups1/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');

like($r = http_get('/ups1/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/empty2'), qr/X-Connection: $n/,
	'unbuffered empty 2');

like($r = http_head('/ups1/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups1/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');

like($r = http_get('/ups1/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');

like($r = http_get('/ups1/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups1/unbuffered/304len2'), qr/X-Connection: $n/,
	'unbuffered 304 with length 2');

# in memory

like($r = http_get('/ups1/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups1/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');

like($r = http_get('/ups1/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups1/inmemory/empty2'), qr/200 OK/, 'inmemory empty 2');

like($r = http_get('/ups1/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups1/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');

like($r = http_get('/ups1/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups1/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');

like(http_get('/ups1/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/ups1/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');

# closed connection tests

like(http_get('/ups1/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/ups1/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/ups1/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/ups1/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/ups1/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/ups1/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

#############################################################################

# buffered

like($r = http_get('/ups2/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');

like($r = http_get('/ups2/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');

like($r = http_get('/ups2/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');

like($r = http_get('/ups2/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');

like($r = http_head('/ups2/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups2/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');

like($r = http_get('/ups2/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/empty2'), qr/X-Connection: $n/, 'buffered empty 2');

like($r = http_get('/ups2/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');

like($r = http_get('/ups2/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/ups2/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');

like($r = http_get('/ups2/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');

like($r = http_get('/ups2/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');

like($r = http_get('/ups2/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');

like($r = http_get('/ups2/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/empty2'), qr/X-Connection: $n/,
	'unbuffered empty 2');

like($r = http_head('/ups2/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups2/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');

like($r = http_get('/ups2/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');

like($r = http_get('/ups2/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups2/unbuffered/304len2'), qr/X-Connection: $n/,
	'unbuffered 304 with length 2');

# in memory

like($r = http_get('/ups2/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups2/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');

like($r = http_get('/ups2/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups2/inmemory/empty2'), qr/200 OK/, 'inmemory empty 2');

like($r = http_get('/ups2/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups2/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');

like($r = http_get('/ups2/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups2/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');

like(http_get('/ups2/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/ups2/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');

# closed connection tests

like(http_get('/ups2/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/ups2/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/ups2/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/ups2/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/ups2/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/ups2/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

###############################################################################

# buffered

like($r = http_get('/ups3/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');

like($r = http_get('/ups3/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');

like($r = http_get('/ups3/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');

like($r = http_get('/ups3/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');

like($r = http_head('/ups3/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_head('/ups3/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');

like($r = http_get('/ups3/buffered/empty1'), qr/200 OK/, 'buffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/empty2'), qr/X-Connection: $n/, 'buffered empty 2');

like($r = http_get('/ups3/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');

like($r = http_get('/ups3/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');

# unbuffered

like($r = http_get('/ups3/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');

like($r = http_get('/ups3/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');

like($r = http_get('/ups3/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');

like($r = http_get('/ups3/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');

like($r = http_get('/ups3/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/empty2'), qr/X-Connection: $n/,
	'unbuffered empty 2');

like($r = http_head('/ups3/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_head('/ups3/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');

like($r = http_get('/ups3/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');

like($r = http_get('/ups3/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1; $n += 1;
like(http_get('/ups3/unbuffered/304len2'), qr/X-Connection: $n/,
	'unbuffered 304 with length 2');

# in memory

like($r = http_get('/ups3/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1; $n += 1; $n = sprintf("%03d", $n);
like(http_get('/ups3/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');

like($r = http_get('/ups3/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1; $n += 1; $n = sprintf("%03d", $n);
like(http_get('/ups3/inmemory/empty2'), qr/200 OK/, 'inmemory empty 2');

like($r = http_get('/ups3/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1; $n += 1; $n = sprintf("%03d", $n);
like(http_get('/ups3/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');

like($r = http_get('/ups3/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1; $n += 1; $n = sprintf("%03d", $n);
like(http_get('/ups3/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');

like(http_get('/ups3/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/ups3/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');

# closed connection tests

like(http_get('/ups3/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/ups3/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/ups3/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/ups3/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/ups3/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/ups3/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

###############################################################################

# buffered

like($r = http_get('/ups4/buffered/length1'), qr/SEE-THIS/, 'buffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/length2'), qr/X-Connection: $n.*SEE/ms, 'buffered 2');
http_get('/ups4/buffered/length/closed');

like($r = http_get('/ups4/buffered/chunked1'), qr/SEE-THIS/, 'buffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/chunked2'), qr/X-Connection: $n/,
	'buffered chunked 2');
http_get('/ups4/buffered/chunked/closed');

like($r = http_get('/ups4/buffered/complex1'), qr/(0123456789){100}/,
	'buffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/complex2'), qr/X-Connection: $n/,
	'buffered complex chunked 2');
http_get('/ups4/buffered/complex/closed');

like($r = http_get('/ups4/buffered/chunk01'), qr/200 OK/, 'buffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/chunk02'), qr/X-Connection: $n/, 'buffered 0 chunk 2');
http_get('/ups4/buffered/chunk0/closed');

like($r = http_head('/ups4/buffered/length/head1'), qr/(?!SEE-THIS)/,
	'buffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups4/buffered/length/head2'), qr/X-Connection: $n/,
	'buffered head 2');
http_get('/ups4/buffered/length/closed');

like($r = http_get('/ups4/buffered/empty1'), qr/200 OK/, 'buffered empty');
like(http_get('/ups4/buffered/empty2'), qr/504 Gateway Time-out/, 'buffered empty 2');
http_get('/ups4/buffered/empty1/closed');

like($r = http_get('/ups4/buffered/304nolen1'), qr/304 Not/, 'buffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/304nolen2'), qr/X-Connection: $n/, 'buffered 304 2');
http_get('/ups4/buffered/304nolen/closed');

like($r = http_get('/ups4/buffered/304len1'), qr/304 Not/,
	'buffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/buffered/304len2'), qr/X-Connection: $n/,
	'buffered 304 with length 2');
http_get('/ups4/buffered/304len/closed');

# unbuffered

like($r = http_get('/ups4/unbuffered/length1'), qr/SEE-THIS/, 'unbuffered');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/length2'), qr/X-Connection: $n/, 'unbuffered 2');
http_get('/ups4/unbuffered/length/closed');

like($r = http_get('/ups4/unbuffered/chunked1'), qr/SEE-THIS/, 'unbuffered chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/chunked2'), qr/X-Connection: $n/,
	'unbuffered chunked 2');
http_get('/ups4/unbuffered/chunked/closed');

like($r = http_get('/ups4/unbuffered/complex1'), qr/(0123456789){100}/,
	'unbuffered complex chunked');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/complex2'), qr/X-Connection: $n/,
	'unbuffered complex chunked 2');
http_get('/ups4/unbuffered/complex/closed');

like($r = http_get('/ups4/unbuffered/chunk01'), qr/200 OK/, 'unbuffered 0 chunk');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/chunk02'), qr/X-Connection: $n/,
	'unbuffered 0 chunk 2');
http_get('/ups4/unbuffered/chunk0/closed');

like($r = http_get('/ups4/unbuffered/empty1'), qr/200 OK/, 'unbuffered empty');
like(http_get('/ups4/unbuffered/empty2'), qr/504 Gateway Time-out/,
	'unbuffered empty 2');
http_get('/ups4/unbuffered/empty1/closed');

like($r = http_head('/ups4/unbuffered/length/head1'), qr/(?!SEE-THIS)/,
	'unbuffered head');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_head('/ups4/unbuffered/length/head2'), qr/X-Connection: $n/,
	'unbuffered head 2');
http_get('/ups4/unbuffered/length/closed');

like($r = http_get('/ups4/unbuffered/304nolen1'), qr/304 Not/, 'unbuffered 304');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/304nolen2'), qr/X-Connection: $n/,
	'unbuffered 304 2');
http_get('/ups4/unbuffered/304nolen/closed');

like($r = http_get('/ups4/unbuffered/304len1'), qr/304 Not/,
	'unbuffered 304 with length');
$r =~ m/X-Connection: (\d+)/; $n = $1;
like(http_get('/ups4/unbuffered/304len2'), qr/X-Connection: $n/,
	'unbuffered 304 with length 2');
http_get('/ups4/unbuffered/304len/closed');

# in memory

like($r = http_get('/ups4/inmemory/length1'), qr/SEE-THIS/, 'inmemory');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups4/inmemory/length2'), qr/SEE-THIS$n/, 'inmemory 2');
http_get('/ups4/inmemory/length/closed');

like($r = http_get('/ups4/inmemory/empty1'), qr/200 OK/, 'inmemory empty');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups4/inmemory/empty2'), qr/200 OK/,
        'inmemory empty 2');
http_get('/ups4/inmemory/empty1/closed');

like($r = http_get('/ups4/inmemory/chunked1'), qr/SEE-THIS/, 'inmemory chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups4/inmemory/chunked2'), qr/SEE-THIS$n/, 'inmemory chunked 2');
http_get('/ups4/inmemory/chunked/closed');

like($r = http_get('/ups4/inmemory/complex1'), qr/(0123456789){100}/,
	'inmemory complex chunked');
$r =~ m/SEE-THIS(\d+)/; $n = $1;
like(http_get('/ups4/inmemory/complex2'), qr/SEE-THIS$n/,
	'inmemory complex chunked 2');
http_get('/ups4/inmemory/complex/closed');

like(http_get('/ups4/inmemory/chunk01'), qr/set: $/, 'inmemory 0 chunk');
like(http_get('/ups4/inmemory/chunk02'), qr/set: $/, 'inmemory 0 chunk 2');
http_get('/ups4/inmemory/chunk0/closed');

# closed connection tests

like(http_get('/ups4/buffered/closed1'), qr/200 OK/, 'buffered closed 1');
like(http_get('/ups4/buffered/closed2'), qr/200 OK/, 'buffered closed 2');
like(http_get('/ups4/unbuffered/closed1'), qr/200 OK/, 'unbuffered closed 1');
like(http_get('/ups4/unbuffered/closed2'), qr/200 OK/, 'unbuffered closed 2');
like(http_get('/ups4/inmemory/closed1'), qr/200 OK/, 'inmemory closed 1');
like(http_get('/ups4/inmemory/closed2'), qr/200 OK/, 'inmemory closed 2');

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $ccount = 0;
	my $rcount = 0;

	# dumb server which is able to keep connections alive

	while (my $client = $server->accept()) {
		Test::Nginx::log_core('||',
			"connection from " . $client->peerhost());
		$client->autoflush(1);
		$ccount++;

		while (1) {
			my $headers = '';
			my $uri = '';

			while (<$client>) {
				Test::Nginx::log_core('||', $_);
				$headers .= $_;
				last if (/^\x0d?\x0a?$/);
			}

			last if $headers eq '';
			$rcount++;

			$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

			if ($uri =~ m/closed/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Connection: close" . CRLF .
					"Content-Length: 12" . CRLF . CRLF .
					"0123456789" . CRLF;
				last;

			} elsif ($uri =~ m/length/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 26" . CRLF . CRLF;
				print $client "TEST-OK-IF-YOU-SEE-THIS" .
					sprintf("%03d", $ccount)
					unless $headers =~ /^HEAD/i;

			} elsif ($uri =~ m/empty/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 0" . CRLF . CRLF;

			} elsif ($uri =~ m/304nolen/) {
				print $client
					"HTTP/1.1 304 Not Modified" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF . CRLF;

			} elsif ($uri =~ m/304len/) {
				print $client
					"HTTP/1.1 304 Not Modified" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Content-Length: 100" . CRLF . CRLF;

			} elsif ($uri =~ m/chunked/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;
				print $client
					"1a" . CRLF .
					"TEST-OK-IF-YOU-SEE-THIS" .
					sprintf("%03d", $ccount) . CRLF .
					"0" . CRLF . CRLF
					unless $headers =~ /^HEAD/i;

			} elsif ($uri =~ m/complex/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;

				if ($headers !~ /^HEAD/i) {
					for my $n (1..100) {
						print $client
							"a" . CRLF .
							"0123456789" . CRLF;
						select undef, undef, undef, 0.01
							if $n % 50 == 0;
					}
					print $client
						"1a" . CRLF .
						"TEST-OK-IF-YOU-SEE-THIS" .
						sprintf("%03d", $ccount) .
						CRLF .
						"0" . CRLF;
					select undef, undef, undef, 0.05;
					print $client CRLF;
				}

			} elsif ($uri =~ m/chunk0/) {
				print $client
					"HTTP/1.1 200 OK" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Transfer-Encoding: chunked" . CRLF .
					CRLF;
				print $client
					"0" . CRLF . CRLF
					unless $headers =~ /^HEAD/i;

			} else {
				print $client
					"HTTP/1.1 404 Not Found" . CRLF .
					"X-Request: $rcount" . CRLF .
					"X-Connection: $ccount" . CRLF .
					"Connection: close" . CRLF . CRLF .
					"Oops, '$uri' not found" . CRLF;
				last;
			}
		}

		close $client;
	}
}

###############################################################################
