#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for dynamic upstream configuration with re-resolvable servers.
# Ensure that upstream configuration is inherited on reload.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

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

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
            proxy_connect_timeout 50ms;
            add_header X-IP $upstream_addr always;
        }

        location /2 {
            proxy_pass http://u2;
            proxy_connect_timeout 50ms;
            add_header X-IP $upstream_addr always;
        }
    }
}

EOF

$t->run_daemon(\&dns_daemon, $t)->waitforfile($t->testdir . '/' . port(8980));
$t->try_run('no resolve in upstream server')->plan(9);

###############################################################################

my $p = port(8081);

update_name({A => '127.0.0.201'});
like(http_get('/'), qr/X-IP: 127.0.0.201:$p/, 'reload - before - request');
like(http_get('/'), qr/X-IP: 127.0.0.201:$p/, 'reload - before - request 2');
like(http_get('/2'), qr/127.0.0.(201:$p, 127.0.0.203|203:$p, 127.0.0.201):$p/,
	'reload - before - many');

update_name({ERROR => 'SERVFAIL'}, 0);

my $conf = $t->read_file('nginx.conf');
$conf =~ s/$p/port(8082)/gmse;
$p = port(8082);
$t->write_file('nginx.conf', $conf);

$t->reload();
waitforworker($t);

like(http_get('/'), qr/X-IP: 127.0.0.201:$p/, 'reload - preresolve - request');
like(http_get('/'), qr/X-IP: 127.0.0.201:$p/, 'reload - preresolve - request 2');
like(http_get('/2'), qr/127.0.0.(201:$p, 127.0.0.203|203:$p, 127.0.0.201):$p/,
	'reload - preresolve - many');

update_name({A => '127.0.0.202'});
like(http_get('/'), qr/X-IP: 127.0.0.202:$p/, 'reload - update - request');
like(http_get('/'), qr/X-IP: 127.0.0.202:$p/, 'reload - update - request 2');
like(http_get('/2'), qr/127.0.0.(202:$p, 127.0.0.203|203:$p, 127.0.0.202):$p/,
	'reload - update - many');

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
