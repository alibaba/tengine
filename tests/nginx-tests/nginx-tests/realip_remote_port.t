#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for nginx realip module, $realip_remote_port variable.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http realip/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

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
            add_header X-Real-Port $realip_remote_port;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('1', '');
$t->run();

plan(skip_all => 'no 127.0.0.1 on host')
	if http_get('/') !~ /X-IP: 127.0.0.1/m;

$t->plan(4);

###############################################################################

my ($sp, $data) = http_sp_get('/1');
like($data, qr/X-Real-Port: $sp/, 'request');

($sp, $data) = http_sp_get('/');
like($data, qr/X-Real-Port: $sp/, 'request redirect');

($sp, $data) = http_sp_xff('/1', '127.0.0.1:123');
like($data, qr/X-Real-Port: $sp/, 'realip');

($sp, $data) = http_sp_xff('/', '127.0.0.1:123');
like($data, qr/X-Real-Port: $sp/, 'realip redirect');

###############################################################################

sub http_sp_get {
	my $s = http_get(shift, start => 1);
	return ($s->sockport(), http_end($s));
}

sub http_sp_xff {
	my ($url, $xff) = @_;

	my $s = http(<<EOF, start => 1);
GET $url HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF

	return ($s->sockport(), http_end($s));
}

###############################################################################
