#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for haproxy protocol.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http access realip/);

$t->write_file_expand('nginx.conf', <<'EOF')->plan(18);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format pp '$remote_addr $request';

    server {
        listen       127.0.0.1:8080 proxy_protocol;
        server_name  localhost;

        set_real_ip_from  127.0.0.1/32;
        add_header X-IP $remote_addr;
        add_header X-PP $proxy_protocol_addr;

        location /pp {
            real_ip_header proxy_protocol;
            error_page 404 =200 /t1;
            access_log %%TESTDIR%%/pp.log pp;

            location /pp_4 {
                deny 192.0.2.1/32;
            }
            location /pp_6 {
                deny 2001:DB8::1/128;
            }
        }
    }
}

EOF

$t->write_file('t1', 'SEE-THIS');
$t->run();

###############################################################################

my $tcp4 = 'PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678' . CRLF;
my $tcp6 = 'PROXY TCP6 2001:Db8::1 2001:Db8::2 1234 5678' . CRLF;
my $unk1 = 'PROXY UNKNOWN' . CRLF;
my $unk2 = 'PROXY UNKNOWN 1 2 3 4 5 6' . CRLF;
my $r;

# no realip, just PROXY header parsing

$r = pp_get('/t1', $tcp4);
like($r, qr/SEE-THIS/, 'tcp4 request');
like($r, qr/X-PP: 192.0.2.1/, 'tcp4 proxy');
unlike($r, qr/X-IP: 192.0.2.1/, 'tcp4 client');

$r = pp_get('/t1', $tcp6);
like($r, qr/SEE-THIS/, 'tcp6 request');
like($r, qr/X-PP: 2001:DB8::1/i, 'tcp6 proxy');
unlike($r, qr/X-IP: 2001:DB8::1/i, 'tcp6 client');

like(pp_get('/t1', $unk1), qr/SEE-THIS/, 'unknown request 1');
like(pp_get('/t1', $unk2), qr/SEE-THIS/, 'unknown request 2');

# realip

$r = pp_get('/pp', $tcp4);
like($r, qr/SEE-THIS/, 'tcp4 request realip');
like($r, qr/X-PP: 192.0.2.1/, 'tcp4 proxy realip');
like($r, qr/X-IP: 192.0.2.1/, 'tcp4 client realip');

$r = pp_get('/pp', $tcp6);
like($r, qr/SEE-THIS/, 'tcp6 request realip');
like($r, qr/X-PP: 2001:DB8::1/i, 'tcp6 proxy realip');
like($r, qr/X-IP: 2001:DB8::1/i, 'tcp6 client realip');

# access

$r = pp_get('/pp_4', $tcp4);
like($r, qr/403 Forbidden/, 'tcp4 access');

$r = pp_get('/pp_6', $tcp6);
like($r, qr/403 Forbidden/, 'tcp6 access');

# client address in access.log

$t->stop();

my $log = $t->read_file('pp.log');
like($log, qr!^192\.0\.2\.1 GET /pp_4!m, 'tcp4 access log');
like($log, qr!^2001:DB8::1 GET /pp_6!mi, 'tcp6 access log');

###############################################################################

sub pp_get {
	my ($url, $proxy) = @_;
	return http($proxy . <<EOF);
GET $url HTTP/1.0
Host: localhost

EOF
}

###############################################################################
