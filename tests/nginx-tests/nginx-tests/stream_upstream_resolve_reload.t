#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for dynamic upstream configuration with re-resolvable servers.
# Ensure that upstream configuration is inherited on reload.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/stream stream_upstream_zone/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u {
        zone z 1m;
        server example.net:%%PORT_8081%% resolve;
    }

    upstream u2 {
        zone z 1m;
        server 127.0.0.203:%%PORT_8081%% max_fails=0;
        server example.net:%%PORT_8081%% resolve max_fails=0;
    }

    # lower the retry timeout after empty reply
    resolver 127.0.0.1:%%PORT_8980_UDP%% valid=1s;
    # retry query shortly after DNS is started
    resolver_timeout 1s;

    log_format test $upstream_addr;

    server {
        listen 127.0.0.1:8082;
        proxy_pass u;
        proxy_connect_timeout 50ms;
        access_log %%TESTDIR%%/cc.log test;
    }

    server {
        listen 127.0.0.1:8083;
        proxy_pass u2;
        proxy_connect_timeout 50ms;
        access_log %%TESTDIR%%/cc2.log test;
    }
}

EOF

$t->run_daemon(\&dns_daemon, $t)->waitforfile($t->testdir . '/' . port(8980));
$t->try_run('no resolve in upstream server')->plan(9);

###############################################################################

my $p = port(8081);

update_name({A => '127.0.0.201'});
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8083))->read();

update_name({ERROR => 'SERVFAIL'}, 0);

my $conf = $t->read_file('nginx.conf');
$conf =~ s/$p/port(8082)/gmse;
$t->write_file('nginx.conf', $conf);

$t->reload();
waitforworker($t);

stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8083))->read();

update_name({A => '127.0.0.202'});
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8082))->read();
stream('127.0.0.1:' . port(8083))->read();

$t->stop();

Test::Nginx::log_core('||', $t->read_file('cc.log'));

open my $f, '<', "${\($t->testdir())}/cc.log" or die "Can't open cc.log: $!";

like($f->getline(), qr/127.0.0.201:$p/, 'log - before');
like($f->getline(), qr/127.0.0.201:$p/, 'log - before 2');

$p = port(8082);

like($f->getline(), qr/127.0.0.201:$p/, 'log - preresolve');
like($f->getline(), qr/127.0.0.201:$p/, 'log - preresolve 2');

like($f->getline(), qr/127.0.0.202:$p/, 'log - update');
like($f->getline(), qr/127.0.0.202:$p/, 'log - update 2');

Test::Nginx::log_core('||', $t->read_file('cc2.log'));

$p = port(8081);

open $f, '<', "${\($t->testdir())}/cc2.log" or die "Can't open cc2.log: $!";

like($f->getline(), qr/127.0.0.(201:$p, 127.0.0.203|203:$p, 127.0.0.201):$p/,
	'log many - before');

$p = port(8082);

like($f->getline(), qr/127.0.0.(201:$p, 127.0.0.203|203:$p, 127.0.0.201):$p/,
	'log many - preresolve');

like($f->getline(), qr/127.0.0.(202:$p, 127.0.0.203|203:$p, 127.0.0.202):$p/,
	'log many - update');

###############################################################################

sub waitforworker {
	my ($t) = @_;

	for (1 .. 30) {
		last if $t->read_file('error.log') =~ /exited with code/;
		select undef, undef, undef, 0.2;
	}
}

sub update_name {
	my ($name, $plan) = @_;

	$plan = 2 if !defined $plan;

	sub sock {
		IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:' . port(8081)
		)
			or die "Can't connect to nginx: $!\n";
	}

	$name->{A} = '' unless $name->{A};
	$name->{ERROR} = '' unless $name->{ERROR};

	my $req =<<EOF;
GET / HTTP/1.0
Host: localhost
X-A: $name->{A}
X-ERROR: $name->{ERROR}

EOF

	my ($gen) = http($req, socket => sock()) =~ /X-Gen: (\d+)/;
	for (1 .. 10) {
		my ($gen2) = http($req, socket => sock()) =~ /X-Gen: (\d+)/;

		# let resolver cache expire to finish upstream reconfiguration
		select undef, undef, undef, 0.5;
		last unless ($gen + $plan > $gen2);
	}
}

###############################################################################

sub reply_handler {
	my ($recv_data, $h) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant SERVFAIL	=> 2;
	use constant NXDOMAIN	=> 3;

	use constant A		=> 1;
	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl) = (0x8180, NOERROR, 1);
	$h = {A => [ "127.0.0.201" ]} unless defined $h;

	# decode name

	my ($len, $offset) = (undef, 12);
	while (1) {
		$len = unpack("\@$offset C", $recv_data);
		last if $len == 0;
		$offset++;
		push @name, unpack("\@$offset A$len", $recv_data);
		$offset += $len;
	}

	$offset -= 1;
	my ($id, $type, $class) = unpack("n x$offset n2", $recv_data);
	my $name = join('.', @name);

	if ($h->{ERROR}) {
		$rcode = SERVFAIL;
		goto bad;
	}

	if ($name eq 'example.net' && $type == A && $h->{A}) {
		map { push @rdata, rd_addr($ttl, $_) } @{$h->{A}};
	}

bad:

	Test::Nginx::log_core('||', "DNS: $name $type $rcode");

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_addr {
	my ($ttl, $addr) = @_;

	my $code = 'split(/\./, $addr)';

	pack 'n3N nC4', 0xc00c, A, IN, $ttl, eval "scalar $code", eval($code);
}

sub dns_daemon {
	my ($t) = @_;
	my ($data, $recv_data, $h);

	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => port(8980),
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	my $control = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:" . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($socket, $control);

	local $SIG{PIPE} = 'IGNORE';

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8980);
	close $fh;
	my $cnt = 0;

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($control == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif ($socket == $fh) {
				$fh->recv($recv_data, 65536);
				$data = reply_handler($recv_data, $h);
				$fh->send($data);
				$cnt++;

			} else {
				$h = process_name($fh, $cnt);
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

# parse dns update

sub process_name {
	my ($client, $cnt) = @_;
	my $port = $client->sockport();

	my $headers = '';
	my $uri = '';
	my %h;

	while (<$client>) {
		$headers .= $_;
		last if (/^\x0d?\x0a?$/);
	}
	return 1 if $headers eq '';

	$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
	return 1 if $uri eq '';

	$headers =~ /X-A: (.*)$/m;
	map { push @{$h{A}}, $_ } split(/ /, $1);
	$headers =~ /X-ERROR: (.*)$/m;
	$h{ERROR} = $1;

	Test::Nginx::log_core('||', "$port: response, 200");
	print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Gen: $cnt

OK
EOF

	return \%h;
}

###############################################################################
