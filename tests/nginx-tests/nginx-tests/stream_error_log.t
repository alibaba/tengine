#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for error_log.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use Sys::Hostname;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/stream/)->plan(34);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

error_log %%TESTDIR%%/e_glob.log info;
error_log %%TESTDIR%%/e_glob2.log info;
error_log syslog:server=127.0.0.1:%%PORT_8983_UDP%% info;

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u {
        server 127.0.0.1:%%PORT_8983_UDP%% down;
    }

    server {
        listen      127.0.0.1:8080;
        proxy_pass  u;

        error_log %%TESTDIR%%/e_debug.log debug;
        error_log %%TESTDIR%%/e_info.log info;
        error_log %%TESTDIR%%/e_emerg.log emerg;
        error_log stderr info;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8081;

        error_log %%TESTDIR%%/e_stream.log info;
        error_log syslog:server=127.0.0.1:%%PORT_8985_UDP%% info;
        error_log syslog:server=127.0.0.1:%%PORT_8984_UDP%% info;
    }
}

EOF

open OLDERR, ">&", \*STDERR;
open STDERR, '>', $t->testdir() . '/stderr' or die "Can't reopen STDERR: $!";
open my $stderr, '<', $t->testdir() . '/stderr'
	or die "Can't open stderr file: $!";

$t->run_daemon(\&stream_daemon);
$t->run_daemon(\&syslog_daemon, port(8983), $t, 's_glob.log');
$t->run_daemon(\&syslog_daemon, port(8984), $t, 's_stream.log');

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforfile($t->testdir . '/s_glob.log');
$t->waitforfile($t->testdir . '/s_stream.log');

$t->run();

open STDERR, ">&", \*OLDERR;

###############################################################################

stream('127.0.0.1:' . port(8080))->io('data');

# error_log levels

SKIP: {
skip "no --with-debug", 1 unless $t->has_module('--with-debug');

isnt(lines($t, 'e_debug.log', '[debug]'), 0, 'file debug in debug');

}

isnt(lines($t, 'e_info.log', '[info]'), 0, 'file info in info');
is(lines($t, 'e_info.log', '[debug]'), 0, 'file debug in info');
isnt(lines($t, 'stderr', '[info]'), 0, 'stderr info in info');
is(lines($t, 'stderr', '[debug]'), 0, 'stderr debug in info');

# multiple error_log

like($t->read_file('e_glob.log'), qr!nginx/[.0-9]+!, 'error global');
like($t->read_file('e_glob2.log'), qr!nginx/[.0-9]+!, 'error global 2');
is_deeply(levels($t, 'e_glob.log'), levels($t, 'e_glob2.log'),
	'multiple error global');

# syslog

parse_syslog_message('syslog', get_syslog('data2', '127.0.0.1:' . port(8082),
	port(8985)));

is_deeply(levels($t, 's_glob.log'), levels($t, 'e_glob.log'),
	'global syslog messages');
is_deeply(levels($t, 's_stream.log'), levels($t, 'e_stream.log'),
	'stream syslog messages');

# error_log context

SKIP: {
skip "relies on error log contents", 5 unless $ENV{TEST_NGINX_UNSAFE};

my $msg = 'no live upstreams while connecting to upstream, '
	. 'client: 127.0.0.1, server: 127.0.0.1:' . port(8080)
	. ', upstream: "u"';

unlike($t->read_file('e_glob.log'), qr/$msg/ms, 'stream error in global');
like($t->read_file('e_info.log'), qr/$msg/ms, 'stream error in info');
like($t->read_file('stderr'), qr/$msg/ms, 'stream error in info stderr');
unlike($t->read_file('e_emerg.log'), qr/$msg/ms, 'stream error in emerg');

$msg = "bytes from/to client:5/4, bytes from/to upstream:4/5";

like($t->read_file('e_stream.log'), qr/$msg/ms, 'stream byte counters');

}

###############################################################################

sub lines {
	my ($t, $file, $pattern) = @_;

	if ($file eq 'stderr') {
		my $value = map { $_ =~ /\Q$pattern\E/ } (<$stderr>);
		$stderr->clearerr();
		return $value;
	}

	my $path = $t->testdir() . '/' . $file;
	open my $fh, '<', $path or return "$!";
	my $value = map { $_ =~ /\Q$pattern\E/ } (<$fh>);
	close $fh;
	return $value;
}

sub levels {
	my ($t, $file) = @_;
	my %levels_hash;

	map { $levels_hash{$_}++; } ($t->read_file($file) =~ /(\[\w+\])/g);

	return \%levels_hash;
}

sub get_syslog {
	my ($data, $peer, $port) = @_;
	my ($s);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(1);
		$s = IO::Socket::INET->new(
			Proto => 'udp',
			LocalAddr => "127.0.0.1:$port"
		);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	stream($peer)->io($data);
	$data = '';

	IO::Select->new($s)->can_read(1.5);
	while (IO::Select->new($s)->can_read(0.1)) {
		my $buffer;
		sysread($s, $buffer, 4096);
		$data .= $buffer;
	}
	$s->close();
	return $data;
}

sub parse_syslog_message {
	my ($desc, $line) = @_;

	ok($line, $desc);

SKIP: {
	skip "$desc timeout", 18 unless $line;

	my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
		'Sep', 'Oct', 'Nov', 'Dec');

	my ($pri, $mon, $mday, $hour, $minute, $sec, $host, $tag, $msg) =
		$line =~ /^<(\d{1,3})>				# PRI
			([A-Z][a-z]{2})\s			# mon
			([ \d]\d)\s(\d{2}):(\d{2}):(\d{2})\s	# date
			([\S]*)\s				# host
			(\w{1,32}):\s				# tag
			(.*)/x;					# MSG

	my $sev = $pri & 0x07;
	my $fac = ($pri & 0x03f8) >> 3;

	ok(defined($pri), "$desc has PRI");
	ok($sev >= 0 && $sev <= 7, "$desc valid severity");
	ok($fac >= 0 && $fac < 24, "$desc valid facility");

	ok(defined($mon), "$desc has month");
	ok((grep $mon, @months), "$desc valid month");

	ok(defined($mday), "$desc has day");
	ok($mday <= 31, "$desc valid day");

	ok(defined($hour), "$desc has hour");
	ok($hour < 24, "$desc valid hour");

	ok(defined($minute), "$desc has minutes");
	ok($minute < 60, "$desc valid minutes");

	ok(defined($sec), "$desc has seconds");
	ok($sec < 60, "$desc valid seconds");

	ok(defined($host), "$desc has host");
	is($host, lc(hostname()), "$desc valid host");

	ok(defined($tag), "$desc has tag");
	like($tag, qr'\w+', "$desc valid tag");

	ok(length($msg) > 0, "$desc valid CONTENT");
}

}

###############################################################################

sub syslog_daemon {
	my ($port, $t, $file) = @_;

	my $s = IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => "127.0.0.1:$port"
	);

	open my $fh, '>', $t->testdir() . '/' . $file;
	select $fh; $| = 1;

	while (1) {
		my $buffer;
		$s->recv($buffer, 4096);
		print $fh $buffer . "\n";
	}
}

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
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

		$buffer = $client->sockport();

		log2o("$client $buffer");

		$client->syswrite($buffer);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
