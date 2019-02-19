#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream access_log module and variables.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_map gzip/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    log_format  test  $server_addr;
    log_format  vars  $connection:$nginx_version:$hostname:$pid;
    log_format  addr  $binary_remote_addr:$remote_addr:$remote_port:
                      $server_addr:$server_port:$upstream_addr;
    log_format  date  $msec!$time_local!$time_iso8601;
    log_format  byte  $bytes_received:$bytes_sent:
                      $upstream_bytes_sent:$upstream_bytes_received;
    log_format  time  $upstream_connect_time:$upstream_first_byte_time:
                      $upstream_session_time;

    access_log  %%TESTDIR%%/off.log test;

    map $server_port $logme {
        %%PORT_8083%%  1;
        default        0;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8080;
        access_log  off;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/time.log time;
    }

    server {
        listen      127.0.0.1:8083;
        listen      127.0.0.1:8084;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/filtered.log test if=$logme;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/complex.log test if=$logme$logme;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/compressed.log test
                    gzip buffer=1m flush=100ms;
    }

    server {
        listen      127.0.0.1:8087;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/varlog_$bytes_sent.log test;
    }

    server {
        listen      127.0.0.1:8088;
        proxy_pass  127.0.0.1:8080;
        access_log  %%TESTDIR%%/vars.log vars;
        access_log  %%TESTDIR%%/addr.log addr;
        access_log  %%TESTDIR%%/date.log date;
        access_log  %%TESTDIR%%/byte.log byte;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->run()->plan(10);

$t->waitforsocket('127.0.0.1:' . port(8080));

###############################################################################

my $str = 'SEE-THIS';

stream('127.0.0.1:' . port(8081))->io($str);
stream('127.0.0.1:' . port(8082))->io($str);
stream('127.0.0.1:' . port(8083))->io($str);
stream('127.0.0.1:' . port(8084))->io($str);
stream('127.0.0.1:' . port(8085))->io($str);
stream('127.0.0.1:' . port(8086))->io($str);
stream('127.0.0.1:' . port(8087))->io($str);

my $dport = port(8088);
my $s = stream("127.0.0.1:$dport");
my $lhost = $s->sockhost();
my $escaped = $s->sockaddr();
$escaped =~ s/([^\x20-\x7e])/sprintf('\\x%02X', ord($1))/gmxe;
my $lport = $s->sockport();
my $uport = port(8080);

$s->io($str);

# wait for file to appear with nonzero size thanks to the flush parameter

for (1 .. 10) {
	last if -s $t->testdir() . '/compressed.log';
	select undef, undef, undef, 0.1;
}

# verify that "gzip" parameter turns on compression

SKIP: {
	eval { require IO::Uncompress::Gunzip; };
	skip("IO::Uncompress::Gunzip not installed", 1) if $@;

	my $gzipped = $t->read_file('compressed.log');
	my $log;
	IO::Uncompress::Gunzip::gunzip(\$gzipped => \$log);
	like($log, qr/^127.0.0.1/, 'compressed log - flush time');
}

# now verify all other logs

$t->stop();

is($t->read_file('off.log'), '', 'log off');
is($t->read_file('filtered.log'), "127.0.0.1\n", 'log filtering');
ok($t->read_file('complex.log'), 'if with complex value');
ok($t->read_file('varlog_3.log'), 'variable in file');

chomp(my $hostname = lc `hostname`);
like($t->read_file('vars.log'), qr/^\d+:[\d.]+:$hostname:\d+$/, 'log vars');
is($t->read_file('addr.log'),
	"$escaped:$lhost:$lport:127.0.0.1:$dport:127.0.0.1:$uport\n",
	'log addr');
like($t->read_file('date.log'), qr#^\d+.\d+![-+\w/: ]+![-+\dT:]+$#, 'log date');
is($t->read_file('byte.log'), "8:3:8:3\n", 'log bytes');
like($t->read_file('time.log'), qr/0\.\d{3}:0\.\d{3}:0\.\d{3}/, 'log time');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => port(8080),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		log2c("(new connection $client)");

		$client->sysread(my $buffer, 65536) or next;

		log2i("$client $buffer");

		$buffer = "ack";

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
