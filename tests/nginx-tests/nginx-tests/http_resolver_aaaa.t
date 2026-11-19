#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for AAAA capable http resolver.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location / {
            resolver    127.0.0.1:%%PORT_8981_UDP%%;
            proxy_pass  http://$host:%%PORT_8080%%/backend;

            proxy_next_upstream http_504 timeout error;
            proxy_intercept_errors on;
            proxy_connect_timeout 50ms;
            error_page 504 502 /50x;
            add_header X-Host $upstream_addr;
        }
        location /two {
            resolver    127.0.0.1:%%PORT_8981_UDP%% 127.0.0.1:%%PORT_8982_UDP%%;
            proxy_pass  http://$host:%%PORT_8080%%/backend;
        }

        location /backend {
            return 200;
        }
        location /50x {
            return 200 $upstream_addr;
        }
    }
}

EOF

$t->try_run('no inet6 support')->plan(72);

$t->run_daemon(\&dns_daemon, port(8981), $t);
$t->run_daemon(\&dns_daemon, port(8982), $t);

$t->waitforfile($t->testdir . '/' . port(8981));
$t->waitforfile($t->testdir . '/' . port(8982));

###############################################################################

my (@n, $response);

my $p0 = port(8080);

like(http_host_header('aaaa.example.net', '/'), qr/\[fe80::1\]/, 'AAAA');
like(http_host_header('cname.example.net', '/'), qr/\[fe80::1\]/, 'CNAME');
like(http_host_header('cname.example.net', '/'), qr/\[fe80::1\]/,
	'CNAME cached');

# CNAME + AAAA combined answer
# demonstrates the name in answer section different from what is asked

like(http_host_header('cname-a.example.net', '/'), qr/\[::1\]/, 'CNAME + AAAA');

# many AAAA records in round robin
# nonexisting IPs enumerated with proxy_next_upstream

like(http_host_header('many.example.net', '/'),
	qr/^\[fe80::(1\]:$p0, \[fe80::2\]:$p0|2\]:$p0, \[fe80::1\]:$p0)$/m,
	'AAAA many');

like(http_host_header('many.example.net', '/'),
	qr/^\[fe80::(1\]:$p0, \[fe80::2\]:$p0|2\]:$p0, \[fe80::1\]:$p0)$/m,
	'AAAA many cached');

# tests for several resolvers specified in directive
# query bad ns, make sure that error responses are not cached

like(http_host_header('2.example.net', '/two'), qr/502 Bad/, 'two ns bad');

# now get correct response

like(http_host_header('2.example.net', '/two'), qr/200 OK/, 'two ns good');

# response is cached, actual request would get error

like(http_host_header('2.example.net', '/two'), qr/200 OK/, 'two ns cached');

# various ipv4/ipv6 combinations

$response = http_host_header('z-z.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'zero zero responses');
like($response, qr/502 Bad/, 'zero zero');

like(http_host_header('z-n.example.net', '/'), qr/^\[fe80::1\]:$p0$/ms,
	'zero AAAA');

$response = http_host_header('z-c.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'zero CNAME responses');
like($response, qr/127.0.0.201:$p0/, 'zero CNAME 1');
like($response, qr/\[fe80::1\]:$p0/, 'zero CNAME 2');

$response = http_host_header('z-cn.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'zero CNAME+AAAA responses');
like($response, qr/\[fe80::1\]:$p0/, 'zero CNAME+AAAA 1');
like($response, qr/\[fe80::2\]:$p0/, 'zero CNAME+AAAA 2');

$response = http_host_header('z-e.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'zero error responses');
like($response, qr/502 Bad/, 'zero error');

like(http_host_header('n-z.example.net', '/'), qr/^127.0.0.201:$p0$/ms,
	'A zero');

$response = http_host_header('n-n.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'A AAAA responses');
like($response, qr/127.0.0.201:$p0/, 'A AAAA 1');
like($response, qr/\[fe80::1\]:$p0/, 'A AAAA 2');

like(http_host_header('n-c.example.net', '/'), qr/^127.0.0.201:$p0$/ms,
	'A CNAME');

$response = http_host_header('n-cn.example.net', '/');
is(@n = $response =~ /$p0/g, 4, 'A CNAME+AAAA responses');
like($response, qr/127.0.0.201:$p0/, 'A CNAME+AAAA 1');
like($response, qr/127.0.0.202:$p0/, 'A CNAME+AAAA 2');
like($response, qr/\[fe80::1\]:$p0/, 'A CNAME+AAAA 3');
like($response, qr/\[fe80::2\]:$p0/, 'A CNAME+AAAA 4');

$response = http_host_header('n-e.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'A error responses');
like($response, qr/502 Bad/, 'A error');

$response = http_host_header('c-z.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'CNAME zero responses');
like($response, qr/502 Bad/, 'CNAME zero');

like(http_host_header('c-n.example.net', '/'), qr/^\[fe80::1\]:$p0$/ms,
	'CNAME AAAA');

$response = http_host_header('c-c.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'CNAME CNAME responses');
like($response, qr/127.0.0.201:$p0/, 'CNAME CNAME 1');
like($response, qr/\[fe80::1\]:$p0/, 'CNAME CNAME 2');

like(http_host_header('c1-c2.example.net', '/'), qr/^\[fe80::1\]:$p0$/ms,
	'CNAME1 CNAME2');

$response = http_host_header('c-cn.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'CNAME CNAME+AAAA responses');
like($response, qr/\[fe80::1\]:$p0/, 'CNAME CNAME+AAAA 1');
like($response, qr/\[fe80::2\]:$p0/, 'CNAME CNAME+AAAA 1');

$response = http_host_header('c-e.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'CNAME error responses');
like($response, qr/502 Bad/, 'CNAME error');

$response = http_host_header('cn-z.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'CNAME+A zero responses');
like($response, qr/127.0.0.201:$p0/, 'CNAME+A zero 1');
like($response, qr/127.0.0.202:$p0/, 'CNAME+A zero 2');

$response = http_host_header('cn-n.example.net', '/');
is(@n = $response =~ /$p0/g, 4, 'CNAME+A AAAA responses');
like($response, qr/127.0.0.201:$p0/, 'CNAME+A AAAA 1');
like($response, qr/127.0.0.202:$p0/, 'CNAME+A AAAA 2');
like($response, qr/\[fe80::1\]:$p0/, 'CNAME+A AAAA 3');
like($response, qr/\[fe80::2\]:$p0/, 'CNAME+A AAAA 4');

$response = http_host_header('cn-c.example.net', '/');
is(@n = $response =~ /$p0/g, 2, 'CNAME+A CNAME responses');
like($response, qr/127.0.0.201:$p0/, 'CNAME+A CNAME 1');
like($response, qr/127.0.0.202:$p0/, 'CNAME+A CNAME 2');

$response = http_host_header('cn-cn.example.net', '/');
is(@n = $response =~ /$p0/g, 4, 'CNAME+A CNAME+AAAA responses');
like($response, qr/127.0.0.201:$p0/, 'CNAME+A CNAME+AAAA 1');
like($response, qr/127.0.0.202:$p0/, 'CNAME+A CNAME+AAAA 2');
like($response, qr/\[fe80::1\]:$p0/, 'CNAME+A CNAME+AAAA 3');
like($response, qr/\[fe80::2\]:$p0/, 'CNAME+A CNAME+AAAA 4');

$response = http_host_header('cn-e.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'CNAME+A error responses');
like($response, qr/502 Bad/, 'CNAME+A error');

$response = http_host_header('e-z.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'error zero responses');
like($response, qr/502 Bad/, 'error zero');

$response = http_host_header('e-n.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'error AAAA responses');
like($response, qr/502 Bad/, 'error AAAA');

$response = http_host_header('e-c.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'error CNAME responses');
like($response, qr/502 Bad/, 'error CNAME');

$response = http_host_header('e-cn.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'error CNAME+AAAA responses');
like($response, qr/502 Bad/, 'error CNAME+AAAA');

$response = http_host_header('e-e.example.net', '/');
is(@n = $response =~ /$p0/g, 0, 'error error responses');
like($response, qr/502 Bad/, 'error error');

###############################################################################

sub http_host_header {
	my ($host, $uri) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
Host: $host

EOF
}

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
	if (($name eq 'aaaa.example.net') || ($name eq 'alias.example.net')) {
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, "fe80::1");
		}

	} elsif ($name eq 'alias2.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, "fe80::1");
		}

	} elsif ($name eq 'alias4.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}

	} elsif ($name eq 'alias6.example.net') {
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, "fe80::1");
		}

	} elsif (($name eq 'many.example.net') && $type == AAAA) {
		$state->{manycnt}++;
		if ($state->{manycnt} > 1) {
			$rcode = SERVFAIL;
		}

		push @rdata, rd_addr6($ttl, 'fe80::1');
		push @rdata, rd_addr6($ttl, 'fe80::2');

	} elsif ($name eq 'cname.example.net') {
		$state->{cnamecnt}++;
		if ($state->{cnamecnt} > 2) {
			$rcode = SERVFAIL;
		}
		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, 'alias', 0xc012);

	} elsif ($name eq 'cname-a.example.net') {
		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, 'alias', 0xc014);

		# points to "alias" set in previous rdata

		if ($type == AAAA) {
			push @rdata, pack('n3N nn8', 0xc031, AAAA, IN, $ttl,
				16, expand_ip6("::1"));
		}

	} elsif ($name eq '2.example.net') {
		if ($port == port(8981)) {
			$state->{twocnt}++;
		}
		if ($state->{twocnt} & 1) {
			$rcode = SERVFAIL;
		}

		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, '::1');
		}

	} elsif ($name eq 'z-z.example.net') {
		# assume no answers given

	} elsif ($name eq 'z-n.example.net') {
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, 'fe80::1');
		}

	} elsif ($name eq 'z-c.example.net') {
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc010);
		}

	} elsif ($name eq 'z-cn.example.net') {
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, 'alias', 0xc011);
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'z-e.example.net') {
		if ($type == AAAA) {
			$rcode = SERVFAIL;
		}

	} elsif ($name eq 'n-z.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}

	} elsif ($name eq 'n-n.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, 'fe80::1');
		}

	} elsif ($name eq 'n-c.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc010);
		}

	} elsif ($name eq 'n-cn.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
			push @rdata, rd_addr($ttl, '127.0.0.202');
		}
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, 'alias', 0xc011);
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'n-e.example.net') {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.201');
		}
		if ($type == AAAA) {
			$rcode = SERVFAIL;
		}

	} elsif ($name eq 'c-z.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, 'alias', 0xc010);
		}

	} elsif ($name eq 'c-n.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, 'alias', 0xc010);
		}
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, "fe80::1");
		}

	} elsif ($name eq 'c-c.example.net') {
		push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
			9, 6, 'alias2', 0xc010);

	} elsif ($name eq 'c1-c2.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias4', 0xc012);
		}
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias6', 0xc012);
		}

	} elsif ($name eq 'c-cn.example.net') {
		push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
			9, 6, 'alias2', 0xc011);

		if ($type == AAAA) {
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'cn-z.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc011);
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.201'));
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.202'));
		}

	} elsif ($name eq 'cn-n.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc011);
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.201'));
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.202'));
		}
		if ($type == AAAA) {
			push @rdata, pack('n3N nn8', 0xc00c, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc00c, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'cn-c.example.net') {
		push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
			9, 6, 'alias2', 0xc011);
		if ($type == A) {
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.201'));
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.202'));
		}

	} elsif ($name eq 'cn-cn.example.net') {
		push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
			9, 6, 'alias2', 0xc012);

		if ($type == A) {
			push @rdata, pack("n3N nC4", 0xc02f, A, IN, $ttl,
				4, split('\.', '127.0.0.201'));
			push @rdata, pack("n3N nC4", 0xc02f, A, IN, $ttl,
				4, split('\.', '127.0.0.202'));
		}
		if ($type == AAAA) {
			push @rdata, pack('n3N nn8', 0xc02f, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc02f, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'cn-e.example.net') {
		if ($type == A) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc011);
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.201'));
			push @rdata, pack("n3N nC4", 0xc02e, A, IN, $ttl,
				4, split('\.', '127.0.0.202'));
		}
		if ($type == AAAA) {
			$rcode = SERVFAIL;
		}


	} elsif ($name eq 'e-z.example.net') {
		if ($type == A) {
			$rcode = SERVFAIL;
		}

	} elsif ($name eq 'e-n.example.net') {
		if ($type == A) {
			$rcode = SERVFAIL;
		}
		if ($type == AAAA) {
			push @rdata, rd_addr6($ttl, 'fe80::1');
		}

	} elsif ($name eq 'e-c.example.net') {
		if ($type == A) {
			$rcode = SERVFAIL;
		}
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa6n", 0xc00c, CNAME, IN, $ttl,
				9, 6, 'alias2', 0xc010);
		}

	} elsif ($name eq 'e-cn.example.net') {
		if ($type == A) {
			$rcode = SERVFAIL;
		}
		if ($type == AAAA) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, 'alias', 0xc011);
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::1"));
			push @rdata, pack('n3N nn8', 0xc02e, AAAA, IN, $ttl,
				16, expand_ip6("fe80::2"));
		}

	} elsif ($name eq 'e-e.example.net') {
		if ($type == A) {
			$rcode = SERVFAIL;
		}
		if ($type == AAAA) {
			$rcode = NXDOMAIN;
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

	# track number of relevant queries

	my %state = (
		cnamecnt	=> 0,
		twocnt		=> 0,
		manycnt		=> 0,
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
