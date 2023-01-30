#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for request_id variable.

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

my $t = Test::Nginx->new()->has(qw/http rewrite ssi/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format id $request_id;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Request-Id $request_id;
        add_header X-blah blah;

        location / {
            ssi on;
        }
        location /body {
            return 200 $request_id;
        }
        location /log {
            access_log %%TESTDIR%%/id.log id;
            return 200;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('add.html', '<!--#include virtual="/body" -->');
$t->run()->plan(12);

###############################################################################

my ($id1) = http_get('/') =~ qr/^X-Request-Id: (.*)\x0d/m;
my ($id2) = http_get('/') =~ qr/^X-Request-Id: (.*)\x0d/m;

like($id1, qr/^[a-z0-9]{32}$/, 'format id 1');
like($id2, qr/^[a-z0-9]{32}$/, 'format id 2');

isnt($id1, $id2, 'different id');

# same request

($id1, $id2) = http_get('/body')
	=~ qr/^X-Request-Id: (.*?)\x0d.*\x0d\x0a(.*)/ms;

like($id1, qr/^[a-z0-9]{32}$/, 'format id 1 - same');
like($id2, qr/^[a-z0-9]{32}$/, 'format id 2 - same');

is($id1, $id2, 'equal id - same');

# subrequest

($id1, $id2) = http_get('/add.html')
	=~ qr/^X-Request-Id: (.*?)\x0d.*\x0d\x0a(.*)/ms;

like($id1, qr/^[a-z0-9]{32}$/, 'format id 1 - sub');
like($id2, qr/^[a-z0-9]{32}$/, 'format id 2 - sub');

is($id1, $id2, 'equal id - sub');

# log

($id1) = http_get('/log') =~ qr/^X-Request-Id: (.*)\x0d/m;

$t->stop();

$id2 = $t->read_file('/id.log');
chomp $id2;

like($id1, qr/^[a-z0-9]{32}$/, 'format id 1 - log');
like($id2, qr/^[a-z0-9]{32}$/, 'format id 2 - log');

is($id1, $id2, 'equal id - log');

###############################################################################
