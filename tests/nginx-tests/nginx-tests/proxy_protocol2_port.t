#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for proxy_protocol_port variable.

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

$t->write_file_expand('nginx.conf', <<'EOF')->plan(8);

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format port $proxy_protocol_port;

    server {
        listen       127.0.0.1:8080 proxy_protocol;
        server_name  localhost;

        add_header X-PP-Port $proxy_protocol_port;
        add_header X-Remote-Port $remote_port;

        location /pp {
            real_ip_header proxy_protocol;
            error_page 404 =200 /t;

            location /pp/real {
                set_real_ip_from  127.0.0.1/32;
            }
        }

        location /log {
            access_log %%TESTDIR%%/port.log port;
        }
    }
}

EOF

$t->write_file('t', 'SEE-THIS');
$t->run();

###############################################################################

my $p = pack("N3C", 0x0D0A0D0A, 0x000D0A51, 0x5549540A, 0x21);
my $tcp4 = $p . pack("CnN2n2", 0x11, 12, 0xc0000201, 0xc0000202, 123, 5678);
my $tcp6 = $p . pack("CnNx8NNx8Nn2", 0x21, 36,
	0x20010db8, 0x00000001, 0x20010db8, 0x00000002, 123, 5678);
my $unk = $p . pack("CnC4", 0x44, 4, 1, 2, 3, 4);

# realip

like(pp_get('/pp', $tcp4), qr/X-PP-Port: 123\x0d/, 'pp port tcp4');
like(pp_get('/pp', $tcp6), qr/X-PP-Port: 123\x0d/, 'pp port tcp6');
unlike(pp_get('/pp', $unk), qr/X-PP-Port/, 'pp port unknown');

# remote_port

like(pp_get('/pp/real', $tcp4), qr/X-Remote-Port: 123\x0d/, 'remote port tcp4');
unlike(pp_get('/pp', $tcp4), qr/X-Remote-Port: 123\x0d/, 'no remote port tcp4');
like(pp_get('/pp/real', $tcp6), qr/X-Remote-Port: 123\x0d/, 'remote port tcp6');
unlike(pp_get('/pp', $tcp6), qr/X-Remote-Port: 123\x0d/, 'no remote port tcp6');

# log

pp_get('/log', $tcp4);

$t->stop();

my $log = $t->read_file('/port.log');
chomp $log;

is($log, 123, 'pp port log');

###############################################################################

sub pp_get {
	my ($url, $proxy) = @_;
	return http($proxy . <<EOF);
GET $url HTTP/1.0
Host: localhost

EOF
}

###############################################################################
