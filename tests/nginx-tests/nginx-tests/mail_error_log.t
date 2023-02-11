#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for nginx mail imap module, error_log directive.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use Sys::Hostname;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/mail imap http rewrite/);

$t->plan(30)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

error_log %%TESTDIR%%/e_glob.log info;
error_log %%TESTDIR%%/e_glob2.log info;
error_log syslog:server=127.0.0.1:%%PORT_8981_UDP%% info;

daemon off;

events {
}

mail {
    proxy_timeout  15s;
    auth_http  http://127.0.0.1:8080/mail/auth;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;

        error_log %%TESTDIR%%/e_debug.log debug;
        error_log %%TESTDIR%%/e_info.log info;
        error_log syslog:server=127.0.0.1:%%PORT_8982_UDP%% info;
        error_log stderr info;
    }

    server {
        listen     127.0.0.1:8145;
        protocol   imap;

        error_log syslog:server=127.0.0.1:%%PORT_8983_UDP%% info;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            add_header Auth-Status OK;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port %%PORT_8144%%;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

open OLDERR, ">&", \*STDERR;
open STDERR, '>', $t->testdir() . '/stderr' or die "Can't reopen STDERR: $!";
open my $stderr, '<', $t->testdir() . '/stderr'
	or die "Can't open stderr file: $!";

$t->run_daemon(\&Test::Nginx::IMAP::imap_test_daemon);
$t->run_daemon(\&syslog_daemon, port(8981), $t, 's_glob.log');
$t->run_daemon(\&syslog_daemon, port(8982), $t, 's_info.log');

$t->waitforsocket('127.0.0.1:' . port(8144));
$t->waitforfile($t->testdir . '/s_glob.log');
$t->waitforfile($t->testdir . '/s_info.log');

$t->run();

open STDERR, ">&", \*OLDERR;

###############################################################################

my $s = Test::Nginx::IMAP->new();
$s->ok('greeting');

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

parse_syslog_message('syslog', get_syslog());

is_deeply(levels($t, 's_glob.log'), levels($t, 'e_glob.log'),
	'global syslog messages');
is_deeply(levels($t, 's_info.log'), levels($t, 'e_info.log'),
	'mail syslog messages');

###############################################################################

sub lines {
	my ($t, $file, $pattern) = @_;

	if ($file eq 'stderr') {
		return map { $_ =~ /\Q$pattern\E/ } (<$stderr>);
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
	my $data = '';
	my ($s);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(1);
		$s = IO::Socket::INET->new(
			Proto => 'udp',
			LocalAddr => '127.0.0.1:' . port(8983)
		);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:' . port(8145))->read();

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

###############################################################################
