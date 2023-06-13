#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream realip module, 'unix:' and hostname in set_real_ip_from.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_realip unix/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen      unix:%%TESTDIR%%/unix.sock proxy_protocol;
        listen      127.0.0.1:8080;
        listen      127.0.0.1:8082 proxy_protocol;
        return      $remote_addr;

        set_real_ip_from unix:;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  unix:%%TESTDIR%%/unix.sock;
    }

    server {
        listen      127.0.0.1:8085 proxy_protocol;
        listen      unix:%%TESTDIR%%/unix2.sock proxy_protocol;
        return      $remote_addr;

        set_real_ip_from localhost;
    }

    server {
        listen      127.0.0.1:8083;
        proxy_pass  127.0.0.1:8085;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  unix:%%TESTDIR%%/unix2.sock;
    }
}

EOF

$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/') ne '127.0.0.1';

$t->plan(4);

###############################################################################

is(pp_get(8081, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1', 'realip unix');
isnt(pp_get(8082, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1', 'realip unix - no match');

is(pp_get(8083, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1', 'realip hostname');
isnt(pp_get(8084, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1', 'realip hostname - no match');

###############################################################################

sub pp_get {
	my ($port, $proxy) = @_;
	stream(PeerPort => port($port))->io($proxy);
}

###############################################################################
