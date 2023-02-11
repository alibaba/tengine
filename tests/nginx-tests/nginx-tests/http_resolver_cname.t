#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http resolver with CNAME.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(11);

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

        location /short {
            resolver    127.0.0.1:%%PORT_8981_UDP%%;
            resolver_timeout 2s;

            proxy_pass  http://$host:%%PORT_8080%%/t;
        }

        location /long {
            resolver    127.0.0.1:%%PORT_8981_UDP%%;
            resolver_timeout 5s;

            proxy_pass  http://$host:%%PORT_8080%%/t;
        }

        location / { }
    }
}

EOF

$t->run_daemon(\&dns_daemon, port(8981), $t);

$t->write_file('t', '');
$t->run();

$t->waitforfile($t->testdir . '/' . port(8981));

###############################################################################

# CNAME pointing to name which times out

like(http_host('cn01.example.net', '/short'), qr/502 Bad/, 'CNAME timeout');

# several requests on CNAME pointing to invalid name

my @s;

push @s, http_host('cn03.example.net', '/long', start => 1);
push @s, http_host('cn03.example.net', '/long', start => 1);

like(http_end(pop @s), qr/502 Bad/, 'invalid CNAME - first');
like(http_end(pop @s), qr/502 Bad/, 'invalid CNAME - last');

# several requests on CNAME pointing to cached name

@s = ();

http_host('a.example.net', '/long');

push @s, http_host('cn04.example.net', '/long', start => 1);
push @s, http_host('cn04.example.net', '/long', start => 1);

like(http_end(pop @s), qr/200 OK/, 'cached CNAME - first');
like(http_end(pop @s), qr/200 OK/, 'cached CNAME - last');

# several requests on CNAME pointing to name being resolved

@s = ();

my $s = http_host('cn06.example.net', '/long', start => 1);

sleep 1;

push @s, http_host('cn05.example.net', '/long', start => 1);
push @s, http_host('cn05.example.net', '/long', start => 1);

like(http_end(pop @s), qr/502 Bad/, 'CNAME in progress - first');
like(http_end(pop @s), qr/502 Bad/, 'CNAME in progress - last');

# several requests on CNAME pointing to name which times out
# 1st request receives CNAME with short ttl
# 2nd request replaces expired CNAME

@s = ();

push @s, http_host('cn07.example.net', '/long', start => 1);

sleep 2;

push @s, http_host('cn07.example.net', '/long', start => 1);

like(http_end(pop @s), qr/502 Bad/, 'CNAME ttl - first');
like(http_end(pop @s), qr/502 Bad/, 'CNAME ttl - last');

# several requests on CNAME pointing to name
# 1st request aborts before name is resolved
# 2nd request finishes with name resolved

@s = ();

push @s, http_host('cn09.example.net', '/long', start => 1);
push @s, http_host('cn09.example.net', '/long', start => 1);

select undef, undef, undef, 0.4;	# let resolver hang on CNAME

close(shift @s);

like(http_end(pop @s), qr/200 OK/, 'abort on CNAME');

like(http_host('cn001.example.net', '/short'), qr/502 Bad/, 'recurse uncached');

###############################################################################

sub http_host {
	my ($host, $uri, %extra) = @_;
	return http(<<EOF, %extra);
GET $uri HTTP/1.0
Host: $host

EOF
}

###############################################################################

sub reply_handler {
	my ($recv_data) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;

	use constant A		=> 1;
	use constant CNAME	=> 5;

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
	if ($name eq 'a.example.net' && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'b.example.net' && $type == A) {
		sleep 2;
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'cn01.example.net') {
		$ttl = 1;
		push @rdata, pack("n3N nCa4n", 0xc00c, CNAME, IN, $ttl,
			7, 4, "cn02", 0xc011);

	} elsif ($name =~ /cn0[268].example.net/) {
		# resolver timeout

		return;

	} elsif ($name eq 'cn03.example.net') {
		select undef, undef, undef, 1.1;
		push @rdata, pack("n3N nC", 0xc00c, CNAME, IN, $ttl, 0);

	} elsif ($name eq 'cn04.example.net') {
		select undef, undef, undef, 1.1;
		push @rdata, pack("n3N nCa1n", 0xc00c, CNAME, IN, $ttl,
			4, 1, "a", 0xc011);

	} elsif ($name eq 'cn05.example.net') {
		select undef, undef, undef, 1.1;
		push @rdata, pack("n3N nCa4n", 0xc00c, CNAME, IN, $ttl,
			7, 4, "cn06", 0xc011);

	} elsif ($name eq 'cn07.example.net') {
		$ttl = 1;
		push @rdata, pack("n3N nCa4n", 0xc00c, CNAME, IN, $ttl,
			7, 4, "cn08", 0xc011);

	} elsif ($name eq 'cn09.example.net') {
		if ($type == A) {
			# await both HTTP requests
			select undef, undef, undef, 0.2;
		}
		push @rdata, pack("n3N nCa1n", 0xc00c, CNAME, IN, $ttl,
			4, 1, "b", 0xc011);

	} elsif ($name eq 'cn052.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.1');
		}

	} elsif ($name =~ /cn0\d+.example.net/) {
		my ($id) = $name =~ /cn(\d+)/;
		$id++;
		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, "cn$id", 0xc012);
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
		$data = reply_handler($recv_data);
		$socket->send($data);
	}
}

###############################################################################
