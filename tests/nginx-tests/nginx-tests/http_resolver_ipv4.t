#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for http resolver with ipv4/ipv6 parameters.

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

my $t = Test::Nginx->new()->has(qw/http proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Addr $upstream_addr always;
        proxy_next_upstream http_403;

        location / {
            proxy_pass  http://$arg_h:%%PORT_8081%%/;
            resolver  127.0.0.1:%%PORT_8980_UDP%% ipv4=on ipv6=on;
        }

        location /ipv4 {
            proxy_pass  http://$arg_h:%%PORT_8081%%/;
            resolver  127.0.0.1:%%PORT_8980_UDP%% ipv4=on ipv6=off;
        }

        location /ipv6 {
            proxy_pass  http://$arg_h:%%PORT_8081%%/;
            resolver  127.0.0.1:%%PORT_8980_UDP%% ipv4=off ipv6=on;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       [::1]:%%PORT_8081%%;
        server_name  localhost;

        location / {
            # return 403;
        }
    }
}

EOF

$t->try_run('no inet6 support')->plan(3);

$t->run_daemon(\&dns_daemon, port(8980), $t);
$t->waitforfile($t->testdir . '/' . port(8980));

###############################################################################

my $p1 = port(8081);

is(get('/'), "127.0.0.1:$p1, [::1]:$p1", 'ipv4 ipv6');
is(get('/ipv4'), "127.0.0.1:$p1", 'ipv4 only');
is(get('/ipv6'), "[::1]:$p1", 'ipv6 only');

###############################################################################

sub get {
	my ($uri) = @_;

	my $r = http_get("$uri?h=example.com");
	my ($addr) = $r =~ /X-Addr: (.+)\x0d/m;
	return $addr;
}

###############################################################################

sub reply_handler {
	my ($recv_data, $port) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;

	use constant A		=> 1;
	use constant AAAA	=> 28;

	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl) = (0x8180, NOERROR, 3600);

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
	if ($name eq 'example.com') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.1');
		}
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, "::1");
		}
	}

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_addr {
	my ($ttl, $addr) = @_;

	my $code = 'split(/\./, $addr)';

	pack 'n3N nC4', 0xc00c, A, IN, $ttl, eval "scalar $code", eval($code);
}

sub expand_ip6 {
	my ($addr) = @_;

	substr ($addr, index($addr, "::"), 2) =
		join "0", map { ":" } (0 .. 8 - (split /:/, $addr) + 1);
	map { hex "0" x (4 - length $_) . "$_" } split /:/, $addr;
}

sub rd_addr6 {
	my ($ttl, $addr) = @_;

	pack 'n3N nn8', 0xc00c, AAAA, IN, $ttl, 16, expand_ip6($addr);
}

sub dns_daemon {
	my ($port, $t) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		$data = reply_handler($recv_data, $port);
		$socket->send($data);
	}
}

###############################################################################
