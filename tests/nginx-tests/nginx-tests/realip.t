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

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-IP $remote_addr;
    real_ip_header    X-Forwarded-For;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /1 {
            set_real_ip_from  127.0.0.1/32;
            set_real_ip_from  10.0.1.0/24;
            real_ip_recursive off;
        }

        location /2 {
            set_real_ip_from  127.0.0.1/32;
            set_real_ip_from  10.0.1.0/24;
            real_ip_recursive on;
        }
    }
}

EOF

$t->write_file('1', '');
$t->write_file('2', '');
$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/1') !~ /X-IP: 127.0.0.1/m;

$t->plan(6);

###############################################################################

like(http_xff('/1', '192.0.2.1'), qr/^X-IP: 192.0.2.1/m, 'realip');
like(http_xff('/1', '10.0.0.1, 192.0.2.1'), qr/^X-IP: 192.0.2.1/m,
        'realip multi');
like(http_xff('/1', '192.0.2.1, 10.0.1.1, 127.0.0.1'),
	qr/^X-IP: 127.0.0.1/m, 'realip recursive off');
like(http_xff('/2', '10.0.1.1, 192.0.2.1, 127.0.0.1'),
	qr/^X-IP: 192.0.2.1/m, 'realip recursive on');

like(http(<<EOF), qr/^X-IP: 10.0.1.1/m, 'realip multi xff recursive off');
GET /1 HTTP/1.0
Host: localhost
X-Forwarded-For: 192.0.2.1
X-Forwarded-For: 127.0.0.1, 10.0.1.1

EOF

like(http(<<EOF), qr/^X-IP: 192.0.2.1/m, 'realip multi xff recursive on');
GET /2 HTTP/1.0
Host: localhost
X-Forwarded-For: 10.0.1.1
X-Forwarded-For: 192.0.2.1
X-Forwarded-For: 127.0.0.1

EOF

###############################################################################

sub http_xff {
	my ($uri, $xff) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################
