#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream upstream name resolved, proxy_next_upstream_tries.

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

my $t = Test::Nginx->new()->has(qw/stream stream_map stream_return/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    map $server_port $upstream {
        %%PORT_8081%%  a.example.com:%%PORT_8090%%;
        %%PORT_8082%%  a.example.com;
        %%PORT_8083%%  nx.example.com:%%PORT_8082%%;
    }

    map $server_port $many {
        default  $server_port.many.example.com;
    }

    resolver  127.0.0.1:%%PORT_8980_UDP%%;

    server {
        listen      127.0.0.1:8081;
        listen      127.0.0.1:8082;
        listen      127.0.0.1:8083;
        proxy_pass  $upstream;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  $many:%%PORT_8090%%;

        proxy_next_upstream_tries 3;
        proxy_connect_timeout 1s;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  $many:%%PORT_8090%%;

        proxy_next_upstream_tries 2;
        proxy_connect_timeout 1s;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  $many:%%PORT_8090%%;

        proxy_next_upstream_tries 0;
        proxy_connect_timeout 1s;
    }

    server {
        listen      127.0.0.1:8090;
        return      SEE-THIS;
    }
}

EOF

$t->run_daemon(\&dns_daemon, port(8980), $t);
$t->run()->plan(8);

$t->waitforfile($t->testdir . '/' . port(8980));

###############################################################################

ok(stream('127.0.0.1:' . port(8081))->read(), 'resolver');
ok(!stream('127.0.0.1:' . port(8082))->read(), 'upstream no port');
ok(!stream('127.0.0.1:' . port(8083))->read(), 'name not found');

ok(stream('127.0.0.1:' . port(8084))->read(), 'resolved tries');
ok(!stream('127.0.0.1:' . port(8085))->read(), 'resolved tries limited');
ok(stream('127.0.0.1:' . port(8086))->read(), 'resolved tries zero');

$t->stop();

SKIP: {
skip "relies on error log contents", 2 unless $ENV{TEST_NGINX_UNSAFE};

my $log = `grep -F '[error]' ${\($t->testdir())}/error.log`;
like($log, qr/no port in upstream "a.example.com"/, 'log - no port');
like($log, qr/nx.example.com could not be resolved/, 'log - not found');

}

###############################################################################

sub reply_handler {
	my ($recv_data, $port) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant A		=> 1;
	use constant IN 	=> 1;

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
	if ($name eq 'a.example.com' && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name =~ qr/many.example.com/ && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.2');
		push @rdata, rd_addr($ttl, '127.0.0.2');
		push @rdata, rd_addr($ttl, '127.0.0.1');
	}

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_addr {
	my ($ttl, $addr) = @_;

	my $code = 'split(/\./, $addr)';

	return pack 'n3N', 0xc00c, A, IN, $ttl if $addr eq '';

	pack 'n3N nC4', 0xc00c, A, IN, $ttl, eval "scalar $code", eval($code);
}

sub dns_daemon {
	my ($port, $t) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr    => '127.0.0.1',
		LocalPort    => $port,
		Proto        => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

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
