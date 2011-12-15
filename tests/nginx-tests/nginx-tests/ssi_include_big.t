#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx ssi bug with big includes.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http ssi rewrite gzip proxy/)->plan(8);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    output_buffers  2 512;
    ssi on;
    gzip on;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /proxy/ {
            proxy_pass http://127.0.0.1:8080/local/;
        }
        location = /local/blah {
            return 204;
        }
    }
}

EOF

$t->write_file('c1.html', 'X' x 1023);
$t->write_file('c2.html', 'X' x 1024);
$t->write_file('c3.html', 'X' x 1025);
$t->write_file('test1.html', '<!--#include virtual="/proxy/blah" -->'
	. '<!--#include virtual="/c1.html" -->');
$t->write_file('test2.html', '<!--#include virtual="/proxy/blah" -->'
	. '<!--#include virtual="/c2.html" -->');
$t->write_file('test3.html', '<!--#include virtual="/proxy/blah" -->'
	. '<!--#include virtual="/c3.html" -->');
$t->write_file('test4.html', '<!--#include virtual="/proxy/blah" -->'
	. ('X' x 1025));

$t->run();

###############################################################################

my $t1 = http_gzip_request('/test1.html');
ok(defined $t1, 'small included file (less than output_buffers)');
http_gzip_like($t1, qr/^X{1023}\Z/, 'small included file content');

my $t2 = http_gzip_request('/test2.html');
ok(defined $t2, 'small included file (equal to output_buffers)');
http_gzip_like($t2, qr/^X{1024}\Z/, 'small included file content');

my $t3 = http_gzip_request('/test3.html');
ok(defined $t3, 'big included file (more than output_buffers)');
http_gzip_like($t3, qr/^X{1025}\Z/, 'big included file content');

my $t4 = http_gzip_request('/test4.html');
ok(defined $t4, 'big ssi main file');
http_gzip_like($t4, qr/^X{1025}\Z/, 'big ssi main file content');

###############################################################################
