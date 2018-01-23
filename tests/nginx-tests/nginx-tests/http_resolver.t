#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http resolver.

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
        server_name  localhost;

        location / {
            resolver    127.0.0.1:8081;
            resolver_timeout 1s;
            proxy_pass  http://$host:8080/backend;

            proxy_next_upstream http_504 timeout error;
            proxy_intercept_errors on;
            proxy_connect_timeout 1s;
            error_page 504 502 /50x;
        }
        location /two {
            resolver    127.0.0.1:8081 127.0.0.1:8082;
            proxy_pass  http://$host:8080/backend;
        }
        location /valid {
            resolver    127.0.0.1:8081 valid=5s;
            proxy_pass  http://$host:8080/backend;
        }
        location /case {
            resolver    127.0.0.1:8081;
            proxy_pass  http://$http_x_name:8080/backend;
        }
        location /invalid {
            proxy_pass  http://$host:8080/backend;
        }
        location /resend {
            resolver    127.0.0.1:8081;
            resolver_timeout 8s;
            proxy_pass  http://$host:8080/backend;
        }
        location /bad {
            resolver    127.0.0.1:8089;
            resolver_timeout 1s;
            proxy_pass  http://$host:8080/backend;
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

$t->run_daemon(\&dns_daemon, 8081, $t);
$t->run_daemon(\&dns_daemon, 8082, $t);
$t->run_daemon(\&dns_daemon, 8089, $t);

$t->run()->plan(32);

$t->waitforfile($t->testdir . '/8081');
$t->waitforfile($t->testdir . '/8082');
$t->waitforfile($t->testdir . '/8089');

###############################################################################

# schedule resend test, which takes about 5 seconds to complete

my $s = http_host_header('id.example.net', '/resend', start => 1);

like(http_host_header('a.example.net', '/'), qr/200 OK/, 'A');

# ensure that resolver serves queries from cache in a case-insensitive manner
# we check this by marking 2nd and subsequent queries on backend with SERVFAIL

http_x_name_header('case.example.net', '/case');
like(http_x_name_header('CASE.example.net', '/case'), qr/200 OK/,
	'A case-insensitive');

like(http_host_header('awide.example.net', '/'), qr/200 OK/, 'A uncompressed');
like(http_host_header('short.example.net', '/'), qr/502 Bad/,
	'A short dns response');

like(http_host_header('nx.example.net', '/'), qr/502 Bad/, 'NXDOMAIN');
like(http_host_header('cname.example.net', '/'), qr/200 OK/, 'CNAME');
like(http_host_header('cname.example.net', '/'), qr/200 OK/,
	'CNAME cached');

# CNAME + A combined answer
# demonstrates the name in answer section different from what is asked

like(http_host_header('cname_a.example.net', '/'), qr/200 OK/, 'CNAME + A');

# CNAME refers to non-existing A

like(http_host_header('cname2.example.net', '/'), qr/502 Bad/, 'CNAME bad');
like(http_host_header('long.example.net', '/'), qr/200 OK/, 'long label');
like(http_host_header('long2.example.net', '/'), qr/200 OK/, 'long name');

# take into account DNAME

like(http_host_header('alias.example.com', '/'), qr/200 OK/, 'DNAME');

# many A records in round robin
# nonexisting IPs enumerated with proxy_next_upstream

like(http_host_header('many.example.net', '/'),
	qr/^127.0.0.20(1:8080, 127.0.0.202:8080|2:8080, 127.0.0.201:8080)$/m,
	'A many');

like(http_host_header('many.example.net', '/'),
	qr/^127.0.0.20(1:8080, 127.0.0.202:8080|2:8080, 127.0.0.201:8080)$/m,
	'A many cached');

# tests for several resolvers specified in directive
# query bad ns, make sure that error responses are not cached

like(http_host_header('2.example.net', '/two'), qr/502 Bad/, 'two ns bad');

# now get correct response

like(http_host_header('2.example.net', '/two'), qr/200 OK/, 'two ns good');

# response is cached, actual request would get error

like(http_host_header('2.example.net', '/two'), qr/200 OK/, 'two ns cached');

# ttl tested with 1st req good and 2nd req bad
# send 1st request and cache its good response

like(http_host_header('ttl.example.net', '/'), qr/200 OK/, 'ttl');

# response is cached, actual request would get error

like(http_host_header('ttl.example.net', '/'), qr/200 OK/, 'ttl cached 1');
like(http_host_header('ttl.example.net', '/'), qr/200 OK/, 'ttl cached 2');

sleep 2;

# expired ttl causes nginx to make actual query

like(http_host_header('ttl.example.net', '/'), qr/502 Bad/, 'ttl expired');

# zero ttl prohibits response caching

like(http_host_header('ttl0.example.net', '/'), qr/200 OK/, 'zero ttl');

TODO: {
local $TODO = 'support for zero ttl';

like(http_host_header('ttl0.example.net', '/'), qr/502 Bad/,
	'zero ttl not cached');

}

# "valid" parameter tested with 1st req good and 2nd req bad
# send 1st request and cache its good response

like(http_host_header('ttl.example.net', '/valid'), qr/200 OK/, 'valid');

# response is cached, actual request would get error

like(http_host_header('ttl.example.net', '/valid'), qr/200 OK/,
	'valid cached 1');
like(http_host_header('ttl.example.net', '/valid'), qr/200 OK/,
	'valid cached 2');

sleep 2;

# expired ttl is overridden with "valid" parameter
# response is taken from cache

like(http_host_header('ttl.example.net', '/valid'), qr/200 OK/,
	'valid overrides ttl');

sleep 4;

# expired "valid" value causes nginx to make actual query

like(http_host_header('ttl.example.net', '/valid'), qr/502 Bad/,
	'valid expired');

# Ensure that resolver respects expired CNAME in CNAME + A combined response.
# When ttl in CNAME is expired, the answer should not be served from cache.
# Catch this by returning SERVFAIL on the 2nd and subsequent queries.

http_host_header('cname_a_ttl2.example.net', '/');

sleep 2;

like(http_host_header('cname_a_ttl2.example.net', '/'), qr/502 Bad/,
	'CNAME + A with expired CNAME ttl');

like(http_host_header('example.net', '/invalid'), qr/502 Bad/, 'no resolver');

like(http_end($s), qr/200 OK/, 'resend after malformed response');

$s = http_get('/bad', start => 1);
my $s2 = http_get('/bad', start => 1);

http_end($s);
ok(http_end($s2), 'timeout handler on 2nd request');

###############################################################################

sub http_host_header {
	my ($host, $uri, %extra) = @_;
	return http(<<EOF, %extra);
GET $uri HTTP/1.0
Host: $host

EOF
}

sub http_x_name_header {
	my ($host, $uri) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
X-Name: $host

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
	if (($name eq 'a.example.net') || ($name eq 'alias.example.net')) {
		if ($type == A || $type == CNAME) {
			push @rdata, rd_addr($ttl, '127.0.0.1');
		}

	} elsif ($name eq 'case.example.net' && $type == A) {
		if (++$state->{casecnt} > 1) {
			$rcode = SERVFAIL;
		}

		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'id.example.net' && $type == A) {
		if (++$state->{idcnt} == 1) {
			$id++;
		}

		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'awide.example.net' && $type == A) {
		push @rdata, pack '(C/a*)3x n2N nC4',
			('awide', 'example', 'net'), A, IN, $ttl,
			4, (127, 0, 0, 1);

	} elsif (($name eq 'many.example.net') && $type == A) {
		$state->{manycnt}++;
		if ($state->{manycnt} > 1) {
			$rcode = SERVFAIL;
		}

		push @rdata, rd_addr($ttl, '127.0.0.201');
		push @rdata, rd_addr($ttl, '127.0.0.202');


	} elsif (($name eq 'short.example.net')) {
		# zero length RDATA in DNS response

		if ($type == A) {
			push @rdata, rd_addr($ttl, '');
		}

	} elsif (($name eq 'alias.example.com')) {
		# example.com.       3600 IN DNAME example.net.

		my @dname = ('example', 'net');
		my $rdlen = length(join '', @dname) + @dname + 1;
		push @rdata, pack("n3N n(C/a*)* x", 0xc012, DNAME, IN, $ttl,
			$rdlen, @dname);

		# alias.example.com. 3600 IN CNAME alias.example.net.

		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, 'alias', 0xc02f);

	} elsif ($name eq 'cname.example.net') {
		$state->{cnamecnt}++;
		if ($state->{cnamecnt} > 2) {
		        $rcode = SERVFAIL;
		}
		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, 'alias', 0xc012);

	} elsif ($name eq 'cname_a.example.net') {
		push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
			8, 5, 'alias', 0xc014);

		# points to "alias" set in previous rdata

		if ($type == A) {
			push @rdata, pack('n3N nC4', 0xc031, A, IN, $ttl,
				4, split(/\./, '127.0.0.1'));
		}

	} elsif ($name eq 'cname_a_ttl2.example.net' && $type == A) {
		push @rdata, pack("n3N nCa18n", 0xc00c, CNAME, IN, 1,
			21, 18, 'cname_a_ttl2_alias', 0xc019);
		if (++$state->{cttl2cnt} >= 2) {
		        $rcode = SERVFAIL;
		}
		push @rdata, pack('n3N nC4', 0xc036, A, IN, $ttl,
			4, split(/\./, '127.0.0.1'));

	} elsif ($name eq 'cname_a_ttl_alias.example.net' && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'cname2.example.net') {
		# points to non-existing A

		push @rdata, pack("n3N nCa2n", 0xc00c, CNAME, IN, $ttl,
			5, 2, 'nx', 0xc02f);

	} elsif ($name eq 'long.example.net') {
		push @rdata, pack("n3N nCA63x", 0xc00c, CNAME, IN, $ttl,
			65, 63, 'a' x 63);

	} elsif (($name eq 'a' x 63) && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'long2.example.net') {
		push @rdata, pack("n3N n(CA63)4x", 0xc00c, CNAME, IN, $ttl, 257,
			63, 'a' x 63, 63, 'a' x 63, 63, 'a' x 63, 63, 'a' x 63);

	} elsif (($name eq 'a' x 63 . '.' . 'a' x 63 . '.' . 'a' x 63 . '.'
			. 'a' x 63) && $type == A)
	{
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq 'ttl.example.net' && $type == A) {
		$state->{ttlcnt}++;
		if ($state->{ttlcnt} == 2 || $state->{ttlcnt} == 4) {
			$rcode = SERVFAIL;
		}

		push @rdata, rd_addr(1, '127.0.0.1');

	} elsif ($name eq 'ttl0.example.net' && $type == A) {
		$state->{ttl0cnt}++;
		if ($state->{ttl0cnt} == 2) {
			$rcode = SERVFAIL;
		}

		push @rdata, rd_addr(0, '127.0.0.1');

	} elsif ($name eq '2.example.net') {
		if ($port == 8081) {
			$state->{twocnt}++;
		}
		if ($state->{twocnt} & 1) {
			$rcode = SERVFAIL;
		}

		if ($type == A) {
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
		ttlcnt       => 0,
		ttl0cnt      => 0,
		cttlcnt      => 0,
		cttl2cnt     => 0,
		manycnt      => 0,
		casecnt      => 0,
		idcnt        => 0,
	);

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		next if $port == 8089;
		$data = reply_handler($recv_data, $port, \%state);
		$socket->send($data);
	}
}

###############################################################################
