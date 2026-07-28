#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for re-resolvable servers with resolver in http upstream.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_zone/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    resolver 127.0.0.1:%%PORT_8980_UDP%%;

    upstream u {
        zone z 1m;
        server example.net:%%PORT_8080%% resolve;
    }

    upstream u1 {
        zone z 1m;
        server example.net:%%PORT_8080%% resolve;
        resolver 127.0.0.1:%%PORT_8981_UDP%%;
    }

    upstream u2 {
        zone z 1m;
        server example.net:%%PORT_8080%% resolve;
        resolver 127.0.0.1:%%PORT_8982_UDP%%;
        resolver_timeout 200s; # for coverage
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$args/t;
            proxy_connect_timeout 50ms;
            add_header X-IP $upstream_addr;
            error_page 502 504 redirect;
        }

    }
}

EOF

$t->run_daemon(\&dns_daemon, $t, port($_), port($_ - 500)) for (8980 .. 8982);
$t->waitforfile($t->testdir . '/' . port($_)) for (8980 .. 8982);

$t->try_run('no resolver in upstream')->plan(6);

###############################################################################

ok(waitfordns(8980), 'resolved');
ok(waitfordns(8981), 'resolved in upstream 1');
ok(waitfordns(8982), 'resolved in upstream 2');

like(http_get('/?u'), qr/127.0.0.200/, 'resolver');
like(http_get('/?u1'), qr/127.0.0.201/, 'resolver upstream 1');
like(http_get('/?u2'), qr/127.0.0.202/, 'resolver upstream 2');

###############################################################################

sub waitfordns {
	my ($port) = @_;

	sub sock {
		my ($port) = @_;
		IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:' . port($port - 500)
		)
			or die "Can't connect to dns control socket: $!\n";
	}

	my $req =<<EOF;
GET / HTTP/1.0
Host: localhost

EOF

	for (1 .. 10) {
		my ($gen) = http($req, socket => sock($port)) =~ /X-Gen: (\d+)/;
		return 1 if $gen >= 2;
		select undef, undef, undef, 0.5;
	}
}

###############################################################################

sub reply_handler {
	my ($recv_data, $port) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant A		=> 1;
	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl) = (0x8180, NOERROR, 1);

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
	if ($name eq 'example.net' && $type == A) {
		if ($port == port(8980)) {
			push @rdata, rd_addr($ttl, "127.0.0.200");
		}

		if ($port == port(8981)) {
			push @rdata, rd_addr($ttl, "127.0.0.201");
		}

		if ($port == port(8982)) {
			push @rdata, rd_addr($ttl, "127.0.0.202");
		}
	}

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
	my ($t, $port, $control_port) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	my $control = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $control_port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($socket, $control);

	local $SIG{PIPE} = 'IGNORE';

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
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
				$data = reply_handler($recv_data, $port);
				$fh->send($data);
				$cnt++;

			} else {
				control_handler($fh, $cnt);
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub control_handler {
	my ($client, $cnt) = @_;
	my $port = $client->sockport();

	my $headers = '';
	my $uri = '';

	while (<$client>) {
		$headers .= $_;
		last if (/^\x0d?\x0a?$/);
	}
	return 1 if $headers eq '';

	$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
	return 1 if $uri eq '';

	Test::Nginx::log_core('||', "$port: response, 200");
	print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Gen: $cnt

OK
EOF
}

###############################################################################
