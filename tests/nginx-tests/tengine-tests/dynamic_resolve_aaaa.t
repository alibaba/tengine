#!/usr/bin/perl

# Copyright (C) 2010-2019 Alibaba Group Holding Limited


# Tests for dynamic resolve ipv6 in upstream module.
#
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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite ipv6/);

my $nginx_conf = <<'EOF';

%%TEST_GLOBALS%%

daemon         off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    resolver 127.0.0.1:8900 valid=1s ipv6=on;
    resolver_timeout 1s;

    upstream backend {
        server www.taobao.com fail_timeout=0s;

        server 127.0.0.4:8081 backup;
    }

    upstream backend1 {
        dynamic_resolve;

        server www.test.com fail_timeout=0s;
        server 127.0.0.4:8081 backup;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header UPS $upstream_addr;
        location /static {
            proxy_pass http://backend;
        }

        location / {
            proxy_pass http://backend1;
            #set $t  www.test.com;
            #proxy_pass http://$t;
        }


        location /50x {
            return 200 $upstream_addr;
        }

        proxy_intercept_errors on;
        error_page 504 502 /50x;
    }
}

EOF

$t->write_file_expand('nginx.conf', $nginx_conf);


$t->run()->plan(2);

$t->run_daemon(\&dns_daemon, 8900, $t);
$t->waitforfile($t->testdir . '/8900');
###############################################################################
my (@n, $response);

unlike(http_get('/static'), qr/127.0.0.4/, 'static resolved should be taobao\' IP addr');
like(http_get('/ipv6'), qr/\[fe80::1\]/, 'dynamic resolve ipv6');

###############################################################################
sub reply_handler {
	my ($recv_data, $port, $state) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant SERVFAIL	=> 2;
	use constant NXDOMAIN	=> 3;

	use constant A		=> 1;
	use constant CNAME	=> 5;
	use constant AAAA	=> 28;
	use constant DNAME	=> 39;

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
	if ($name eq 'www.test.com') {
		if ($type == AAAA || $type == CNAME) {
			push @rdata, rd_addr6($ttl, "fe80::1");
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
		LocalAddr    => '127.0.0.1',
		LocalPort    => $port,
		Proto        => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	# track number of relevant queries

	my %state = (
		cnamecnt     => 0,
		twocnt       => 0,
		manycnt      => 0,
	);

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		$data = reply_handler($recv_data, $port, \%state);
		$socket->send($data);
	}
}


###############################################################################
