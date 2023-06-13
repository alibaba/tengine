#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for haproxy protocol.

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

my $t = Test::Nginx->new()->has(qw/http access realip/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format pp $remote_addr:$remote_port;

    add_header X-IP $remote_addr!$remote_port;
    add_header X-PP $proxy_protocol_addr!$proxy_protocol_port;
    add_header X-PPS $proxy_protocol_server_addr!$proxy_protocol_server_port;

    server {
        listen       127.0.0.1:8080 proxy_protocol;
        server_name  localhost;

        set_real_ip_from  127.0.0.1/32;

        location /pp {
            real_ip_header proxy_protocol;
            error_page 404 =200 /t1;

            location /pp_4 {
                deny 192.0.2.1/32;
                access_log %%TESTDIR%%/pp4.log pp;
            }

            location /pp_6 {
                deny 2001:DB8::1/128;
                access_log %%TESTDIR%%/pp6.log pp;
            }
        }

        location / { }
    }
}

EOF

$t->write_file('t1', 'SEE-THIS');
$t->run()->plan(28);

###############################################################################

my $p = pack("N3C", 0x0D0A0D0A, 0x000D0A51, 0x5549540A, 0x21);
my $tcp4 = $p . pack("CnN2n2", 0x11, 12, 0xc0000201, 0xc0000202, 123, 567);
my $tcp6 = $p . pack("CnNx8NNx8Nn2", 0x21, 36,
	0x20010db8, 0x00000001, 0x20010db8, 0x00000002, 123, 567);
my $tlv = $p . pack("CnN2n2x9", 0x11, 21, 0xc0000201, 0xc0000202, 123, 567);
my $unk1 = $p . pack("Cxx", 0x01);
my $unk2 = $p . pack("CnC4", 0x41, 4, 1, 2, 3, 4);
my $r;

# no realip, just PROXY header parsing

$r = pp_get('/t1', $tcp4);
like($r, qr/SEE-THIS/, 'tcp4 request');
like($r, qr/X-PP: 192.0.2.1!123\x0d/, 'tcp4 proxy');
like($r, qr/X-PPS: 192.0.2.2!567\x0d/, 'tcp4 proxy server');
unlike($r, qr/X-IP: (192.0.2.1|[^!]+!123\x0d)/, 'tcp4 client');

$r = pp_get('/t1', $tcp6);
like($r, qr/SEE-THIS/, 'tcp6 request');
like($r, qr/X-PP: 2001:DB8::1!123\x0d/i, 'tcp6 proxy');
like($r, qr/X-PPS: 2001:DB8::2!567\x0d/i, 'tcp6 proxy server');
unlike($r, qr/X-IP: (2001:DB8::1|[^!]+!123\x0d)/i, 'tcp6 client');

$r = pp_get('/t1', $tlv);
like($r, qr/SEE-THIS/, 'tlv request');
like($r, qr/X-PP: 192.0.2.1!123\x0d/, 'tlv proxy');
like($r, qr/X-PPS: 192.0.2.2!567\x0d/, 'tlv proxy server');
unlike($r, qr/X-IP: (192.0.2.1|[^!]+!123\x0d)/, 'tlv client');

$r = pp_get('/t1', $unk1);
like($r, qr/SEE-THIS/, 'unknown request 1');
like($r, qr/X-PP: !\x0d/, 'unknown proxy 1');
like($r, qr/X-PPS: !\x0d/, 'unknown proxy server 1');

$r = pp_get('/t1', $unk2);
like($r, qr/SEE-THIS/, 'unknown request 2');
like($r, qr/X-PP: !\x0d/, 'unknown proxy 2');
like($r, qr/X-PPS: !\x0d/, 'unknown proxy server 2');

# realip

$r = pp_get('/pp', $tcp4);
like($r, qr/SEE-THIS/, 'tcp4 request realip');
like($r, qr/X-PP: 192.0.2.1!123\x0d/, 'tcp4 proxy realip');
like($r, qr/X-IP: 192.0.2.1!123\x0d/, 'tcp4 client realip');

$r = pp_get('/pp', $tcp6);
like($r, qr/SEE-THIS/, 'tcp6 request realip');
like($r, qr/X-PP: 2001:DB8::1!123\x0d/i, 'tcp6 proxy realip');
like($r, qr/X-IP: 2001:DB8::1!123\x0d/i, 'tcp6 client realip');

# access

$r = pp_get('/pp_4', $tcp4);
like($r, qr/403 Forbidden/, 'tcp4 access');

$r = pp_get('/pp_6', $tcp6);
like($r, qr/403 Forbidden/, 'tcp6 access');

# client address in access.log

$t->stop();

is($t->read_file('pp4.log'), "192.0.2.1:123\n", 'tcp4 log');
is($t->read_file('pp6.log'), "2001:db8::1:123\n", 'tcp6 log');

###############################################################################

sub pp_get {
	my ($url, $proxy) = @_;
	return http($proxy . <<EOF);
GET $url HTTP/1.0
Host: localhost

EOF
}

###############################################################################
