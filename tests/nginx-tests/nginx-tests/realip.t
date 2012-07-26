#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx realip module.

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

my $t = Test::Nginx->new()->has(qw/http realip/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    set_real_ip_from  127.0.0.1/32;
    real_ip_header    X-Forwarded-For;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-IP $remote_addr;
        }
    }
}

EOF

$t->write_file('1', '');
$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/1') !~ /X-IP: 127.0.0.1/m;

$t->plan(2);

###############################################################################

like(http_xff('192.0.2.1'), qr/^X-IP: 192.0.2.1/m, 'realip');
like(http_xff('10.0.0.1, 192.0.2.1'), qr/^X-IP: 192.0.2.1/m, 'realip multi');

###############################################################################

sub http_xff {
	my ($xff) = @_;
	return http(<<EOF);
GET /1 HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################
