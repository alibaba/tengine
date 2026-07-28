#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for http tunnel module, tunnel_next_upstream directive.

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

my $t = Test::Nginx->new()->has(qw/http tunnel/);

(my $conf = <<'EOF') =~ s/127.0.0.1:8092/bad_addr(0)/ge;

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream err.example.net {
        server 127.0.0.1:8092;
        server 127.0.0.1:8086;
    }

    resolver 127.0.0.1:%%PORT_8987_UDP%%;
    resolver_timeout 1s;

    tunnel_read_timeout 1s;
    tunnel_connect_timeout 1s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        tunnel_pass;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        tunnel_pass;
        tunnel_next_upstream off;
    }

    server {
        listen       127.0.0.1:8082;
        server_name  localhost;

        tunnel_pass;
        tunnel_next_upstream timeout;
    }

    server {
        listen       127.0.0.1:8083;
        server_name  localhost;

        tunnel_pass err.example.net;
        tunnel_next_upstream error;
    }

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;

        tunnel_pass;
        tunnel_next_upstream_tries 2;
    }

    server {
        listen       127.0.0.1:8085;
        server_name  localhost;

        tunnel_pass;
        tunnel_next_upstream_timeout 500ms;
    }
}

EOF

$t->write_file_expand('nginx.conf', $conf);

$t->write_file('index.html', 'SUCCESS');
$t->write_file('50x.html', 'ERROR');

$t->run_daemon(\&dns_daemon, $t)->waitforfile($t->testdir . '/' . port(8987))
	or die "dns daemon failed to start\n";

$t->run_daemon(\&http_daemon, port(8086))
	->waitforsocket('127.0.0.1:' . port(8086))
	or die 'http daemon failed to start at 127.0.0.1:' . port(8086). "\n";

$t->run_daemon(\&http_daemon, port(8087), response_delay => 2)
	->waitforsocket('127.0.0.1:' . port(8087))
	or die 'http daemon failed to start at 127.0.0.1:' . port(8087). "\n";

$t->try_run('no tunnel')->plan(8);

###############################################################################

my $p = port(8086);

is(proxy_get("/", '127.0.0.1:' . port(8087), port(8080)), 'HTTP/1.1 ',
	'tunnel read timeout');
like(proxy_get("/", bad_addr(1), port(8080)), qr/504 Gateway Time-out/,
	'tunnel connect timeout');
like(proxy_get("/", "nxt.example.net:$p", port(8080)), qr/SEE-THIS/,
	'tunnel next upstream default');
like(proxy_get("/", 'off.example.net:80', port(8081)), qr/502 Bad Gateway/,
	'tunnel next upstream - off');
like(proxy_get("/", "to.example.net:$p", port(8082)), qr/SEE-THIS/,
	'tunnel next upstream - timeout');
like(proxy_get("/", "err.example.net:$p", port(8083)), qr/SEE-THIS/,
	'tunnel next upstream - error');
unlike(proxy_get("/", "try.example.net:$p", port(8084)), qr/SEE-THIS/,
	'tunnel next upstream tries');
like(proxy_get("/", "uto.example.net:$p", port(8085)), qr/504 Gateway Time-out/,
	'tunnel next upstream timeout');

###############################################################################

sub bad_addr {
	my @addr = ( '127.0.0.1', '240.0.0.1' );
	$addr[$^O eq 'MSWin32' ^ shift] . ':' . port(8092);
}

sub proxy_get {
	my ($uri, $host, $proxy_port) = @_;
	my $reply = '';

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . $proxy_port,
	)
		or die "Can't connect to proxy 127.0.0.1:$proxy_port $!\n";

	http_connect($host, socket => $s, start => 1);

	while (<$s>) {
		$reply .= $_;
		last if /^\r?\n$/;
	}

	if ($reply =~ /200 OK/) {
		log_in($reply);
		return http_get($uri, socket => $s);

	} elsif ($reply =~ /Content-Length:\s*(\d+)/i) {
		read ($s, $_, $1);
		$reply .= $_;
	}

	$s->close;
	log_in($reply);
	return $reply;
}

sub http_connect {
	my ($host, %extra) = @_;

	return http(<<EOF, %extra);
CONNECT $host HTTP/1.1
Host: $host

EOF
}

###############################################################################

sub reply_handler {
	my ($recv_data, $port, %extra) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant A		=> 1;
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
	if ($name eq 'to.example.net' or $name eq 'uto.example.net') {
		if ($type == A) {
			if ($^O eq 'MSWin32') {
				push @rdata, rd_addr($ttl, '127.0.0.3');
				push @rdata, rd_addr($ttl, '127.0.0.1');
			} else {
				push @rdata, rd_addr($ttl, '240.0.0.1');
				push @rdata, rd_addr($ttl, '127.0.0.1');
			}
		}
	} elsif ($name eq 'nxt.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '240.0.0.1');
			push @rdata, rd_addr($ttl, '127.0.0.3');
			push @rdata, rd_addr($ttl, '127.0.0.1');
		}
	} elsif ($name eq 'try.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.3');
			push @rdata, rd_addr($ttl, '240.0.0.1');
			push @rdata, rd_addr($ttl, '127.0.0.1');
		}
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
	my ($t) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => port(8987),
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8987);
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		$data = reply_handler($recv_data);
		$socket->send($data);
	}
}

sub http_daemon {
	my ($port, %extra) = @_;

	my $server = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'tcp',
		Listen => 5,
		Reuse => 1,
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		my $headers = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		my $uri = $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i ? $1 : '';

		if ($uri eq '/') {
			print $client 'HTTP/1.1 ';
			select undef, undef, undef, $extra{response_delay}
				if defined $extra{response_delay};
			print $client <<"EOF";
200 OK
Connection: close

SEE-THIS
EOF

		}

		close $client;
	}
}

###############################################################################
