#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream variables.

###############################################################################

use warnings;
use strict;

use Test::More;

use Sys::Hostname;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream dgram /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return udp/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen  127.0.0.1:8080;
        return  $connection:$nginx_version:$hostname:$pid:$bytes_sent;
    }

    server {
        listen  127.0.0.1:8081;
        listen  [::1]:%%PORT_8081%%;
        return  $remote_addr:$remote_port:$server_addr:$server_port;
    }

    server {
        listen  127.0.0.1:8082;
        proxy_pass  [::1]:%%PORT_8081%%;
    }

    server {
        listen  127.0.0.1:8083;
        listen  [::1]:%%PORT_8083%%;
        return  $binary_remote_addr;
    }

    server {
        listen  127.0.0.1:8084;
        proxy_pass  [::1]:%%PORT_8083%%;
    }

    server {
        listen  127.0.0.1:8085;
        return  $msec!$time_local!$time_iso8601;
    }

    server {
        listen  127.0.0.1:8086;
        listen  127.0.0.1:%%PORT_8987_UDP%% udp;
        return  $protocol;
    }
}

EOF

$t->try_run('no inet6 support')->plan(8);

###############################################################################

my $hostname = lc hostname();
like(stream('127.0.0.1:' . port(8080))->read(),
	qr/^\d+:[\d.]+:$hostname:\d+:0$/, 'vars');

my $dport = port(8081);
my $s = stream("127.0.0.1:$dport");
my $lport = $s->sockport();
is($s->read(), "127.0.0.1:$lport:127.0.0.1:$dport", 'addr');

my $data = stream('127.0.0.1:' . port(8082))->read();
like($data, qr/^::1:\d+:::1:\d+$/, 'addr ipv6');

$data = stream('127.0.0.1:' . port(8083))->read();
is(unpack("H*", $data), '7f000001', 'binary addr');

$data = stream('127.0.0.1:' . port(8084))->read();
is(unpack("H*", $data), '0' x 31 . '1', 'binary addr ipv6');

$data = stream('127.0.0.1:' . port(8085))->read();
like($data, qr#^\d+.\d+![-+\w/: ]+![-+\dT:]+$#, 'time');

is(stream('127.0.0.1:' . port(8086))->read(), 'TCP', 'protocol TCP');
is(dgram('127.0.0.1:' . port(8987))->io('.'), 'UDP', 'protocol UDP');

###############################################################################
