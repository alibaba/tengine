#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for proxy_protocol_port variable.

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

my $t = Test::Nginx->new()->has(qw/http realip/)
	->write_file_expand('nginx.conf', <<'EOF');

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
$t->run()->plan(8);

###############################################################################

my $tcp4 = 'PROXY TCP4 192.0.2.1 192.0.2.2 123 5678' . CRLF;
my $tcp6 = 'PROXY TCP6 2001:Db8::1 2001:Db8::2 123 5678' . CRLF;
my $unk = 'PROXY UNKNOWN 1 2 3 4 5 6' . CRLF;

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
