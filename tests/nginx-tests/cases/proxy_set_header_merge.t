#!/usr/bin/perl -w

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

my $t = Test::Nginx->new()->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
   %%TEST_GLOBALS_HTTP%%

   proxy_header_merge_method  append_not_set;

   proxy_set_header   AA aa;
   proxy_set_header   BB oldbb;

   server {
	listen    8080;

	proxy_set_header CC cc;
	proxy_set_header BB bb;

	location /test1 {
	    proxy_set_header IP $remote_addr;
	    proxy_set_header CC "";
	    proxy_pass http://localhost:9999/test1;
	}

	location /test2 {
	    proxy_set_header CC $request_method;
	    proxy_pass http://localhost:9999/test2;
	}

    }

    server {
	listen   9999;

	location /test1 {
	    return 200 "$http_aa,$http_bb,$http_cc,$http_ip";
	}

	location /test2 {
	    return 200 "$http_aa,$http_bb,$http_cc";
	}

    }
}

EOF
###############################################################################
$t->run();

my $r;

$r = http_get('/test1');
#warn $r;
like($r, qr/aa,bb,,127.0.0.1/, 'merge header and replace');


$r = http_get('/test2');
#warn $r;
like($r, qr/aa,bb,GET/, 'merge header and replace by var');

$t->stop();
###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
   %%TEST_GLOBALS_HTTP%%

   #proxy_header_merge_method  default;

   proxy_set_header   AA aa;
   proxy_set_header   BB oldbb;

   server {
	listen    8080;

	proxy_set_header CC cc;
	proxy_set_header BB bb;

	location /test1 {
	    proxy_pass http://localhost:9999/test1;
	}

	location /test2 {
	    proxy_set_header CC $request_method;
	    proxy_pass http://localhost:9999/test2;
	}

    }

    server {
	listen   9999;

	location /test1 {
	    return 200 "$http_aa,$http_bb,$http_cc,$http_ip";
	}

	location /test2 {
	    return 200 "$http_aa,$http_bb,$http_cc";
	}

    }
}

EOF
###############################################################################
$t->run();

$r = http_get('/test1');
#warn $r;
like($r, qr/,bb,cc,/, 'merge header and replace');


$r = http_get('/test2');
#warn $r;
like($r, qr/,,GET/, 'merge header and replace by var');
