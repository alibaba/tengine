#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for embedded perl module.

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

my $t = Test::Nginx->new()->has(qw/http perl ssi/)->plan(3)
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
            ssi on;
        }

        location /dummy {
            perl 'sub foo { my $r = shift; $r->print(join ",", @_); }';
        }
    }
}

EOF

$t->write_file('t1.html', 'X<!--#perl sub="foo" arg="arg1" -->X');
$t->write_file('t2.html', 'X<!--#perl sub="foo" arg="arg1" arg="arg2" -->X');
$t->write_file('noargs.html', 'X<!--#perl sub="foo" -->X');

$t->run();

###############################################################################

like(http_get('/t1.html'), qr/Xarg1X/, 'perl ssi response');
like(http_get('/t2.html'), qr/Xarg1,arg2X/, 'perl ssi two args');
like(http_get('/noargs.html'), qr/XX/, 'perl ssi noargs');

###############################################################################
