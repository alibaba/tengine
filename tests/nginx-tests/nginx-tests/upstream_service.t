#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for dynamic upstream configuration with service (SRV) feature.

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

    upstream u {
        zone z 1m;
        server example.net resolve service=http max_fails=0;
    }

    upstream u2 {
        zone z2 1m;
        server example.net resolve service=_http._tcp;
    }

    upstream u3 {
        zone z3 1m;
        server trunc.example.net resolve service=http;
        resolver 127.0.0.1:%%PORT_8982_UDP%% valid=1s;
    }

    # lower the retry timeout after empty reply
    resolver 127.0.0.1:%%PORT_8981_UDP%% valid=1s;
    # retry query shortly after DNS is started
    resolver_timeout 1s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-IP $upstream_addr;
        error_page 502 504 redirect;
        proxy_connect_timeout 50ms;

        location / {
            proxy_pass http://u/t;
        }

        location /full {
            proxy_pass http://u2/t;
        }

        location /trunc {
            proxy_pass http://u3/t;
        }

        location /t { }
    }
}

EOF

$t->write_file('t', '');

$t->run_daemon(\&dns_daemon, port(8981), port(8084), $t)
	->waitforfile($t->testdir . '/' . port(8981));

$t->run_daemon(\&dns_daemon, port(8982), port(8085), $t, tcp => 1)
	->waitforfile($t->testdir . '/' . port(8982));
port(8982, socket => 1)->close();

$t->try_run('no service in upstream server')->plan(38);

###############################################################################

my ($r, @n);
my ($p0, $p2, $p3) = (port(8080), port(8082), port(8083));

update_name({A => '127.0.0.201', SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A');
like($r, qr/127.0.0.201:$p0/, 'A 1');

# fully specified service

$r = http_get('/full');
is(@n = $r =~ /:$p0/g, 1, 'A full');
like($r, qr/127.0.0.201:$p0/, 'A full 1');

# A changed

update_name({A => '127.0.0.202', SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A changed');
like($r, qr/127.0.0.202:$p0/, 'A changed 1');

# 1 more A added

update_name({A => '127.0.0.201 127.0.0.202', SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 2, 'A A');
like($r, qr/127.0.0.201:$p0/, 'A A 1');
like($r, qr/127.0.0.202:$p0/, 'A A 2');

# 1 A removed, 2 AAAA added

update_name({A => '127.0.0.201', AAAA => 'fe80::1 fe80::2',
	SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 3, 'A AAAA AAAA responses');
like($r, qr/127.0.0.201:$p0/, 'A AAAA AAAA 1');
like($r, qr/\[fe80::1\]:$p0/, 'A AAAA AAAA 2');
like($r, qr/\[fe80::1\]:$p0/, 'A AAAA AAAA 3');

# all records removed

update_name({SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 0, 'empty SRV response');

# all SRV records removed

update_name();
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 0, 'empty response');

# A added after empty

update_name({A => '127.0.0.201', SRV => "1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A added');
like($r, qr/127.0.0.201:$p0/, 'A added 1');

# SRV changed its weight

update_name({A => '127.0.0.201', SRV => "1 6 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'SRV weight');
like($r, qr/127.0.0.201:$p0/, 'SRV weight 1');

# changed to CNAME

update_name({CNAME => 'alias'}, 2, 2);
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'CNAME');
like($r, qr/127.0.0.203:$p0/, 'CNAME 1');

# bad SRV reply should not affect existing upstream configuration

update_name({CNAME => 'alias', ERROR => 'SERVFAIL'}, 1, 0);
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'ERROR');
like($r, qr/127.0.0.203:$p0/, 'ERROR 1');
update_name({ERROR => ''}, 1, 0);

# 2 equal SRV RR

update_name({A => '127.0.0.201',
	SRV => "1 5 $p0 example.net;1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 2, 'SRV same');
like($r, qr/127.0.0.201:$p0, 127.0.0.201:$p0/, 'SRV same peers');

# all equal records removed

update_name();
$r = http_get('/');
is(@n = $r =~ /:($p0|$p2|$p3)/g, 0, 'SRV same removed');

# 2 different SRV RR

update_name({A => '127.0.0.201',
	SRV => "1 5 $p2 example.net;2 6 $p3 alias.example.net"}, 1, 2);
$r = http_get('/');
is(@n = $r =~ /:($p2|$p3)/g, 2, 'SRV diff');
like($r, qr/127.0.0.201:$p2/, 'SRV diff 1');
like($r, qr/127.0.0.203:$p3/, 'SRV diff 2');

# all different records removed

update_name();
$r = http_get('/');
is(@n = $r =~ /:($p0|$p2|$p3)/g, 0, 'SRV diff removed');

# bad subordinate reply should not affect existing upstream configuration

update_name({A => '127.0.0.201',
	SRV => "1 5 $p0 example.net;1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:($p0)/g, 2, 'SRV diff');
like($r, qr/127.0.0.201:$p0/, 'SRV diff 1');
like($r, qr/127.0.0.201:$p0/, 'SRV diff 2');

update_name({A => '127.0.0.201', SERROR => 'SERVFAIL',
	SRV => "1 5 $p0 example.net;1 5 $p0 example.net"});
$r = http_get('/');
is(@n = $r =~ /:($p0)/g, 2, 'SRV diff');
like($r, qr/127.0.0.201:$p0/, 'SRV diff 1');
like($r, qr/127.0.0.201:$p0/, 'SRV diff 2');

# SRV trunc

$r = http_get('/trunc');
is(@n = $r =~ /:$p0/g, 1, 'tcp request');
like($r, qr/127.0.0.1:$p0/, 'tcp request 1');

###############################################################################

sub update_name {
	my ($name, $plan, $plan6) = @_;

	$plan = 1, $plan6 = 0 if !defined $name;
	$plan = $plan6 = 1 if !defined $plan;
	$plan += $plan6 + $plan6;

	sub sock {
		IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:' . port(8084)
		)
			or die "Can't connect to nginx: $!\n";
	}

	$name->{A} = '' unless $name->{A};
	$name->{AAAA} = '' unless $name->{AAAA};
	$name->{CNAME} = '' unless $name->{CNAME};
	$name->{ERROR} = '' unless $name->{ERROR};
	$name->{SERROR} = '' unless $name->{SERROR};
	$name->{SRV} = '' unless $name->{SRV};

	my $req =<<EOF;
GET / HTTP/1.0
Host: localhost
X-A: $name->{A}
X-AAAA: $name->{AAAA}
X-CNAME: $name->{CNAME}
X-ERROR: $name->{ERROR}
X-SERROR: $name->{SERROR}
X-SRV: $name->{SRV}

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
	my ($recv_data, $h, $cnt, $tcp) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant FORMERR	=> 1;
	use constant SERVFAIL	=> 2;
	use constant NXDOMAIN	=> 3;

	use constant A		=> 1;
	use constant CNAME	=> 5;
	use constant AAAA	=> 28;
	use constant SRV	=> 33;

	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl, $port) = (0x8180, NOERROR, 3600, port(8080));
	$h = {A => [ "127.0.0.1" ], SRV => [ "1 5 $port example.net" ]}
		unless defined $h;

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

	if ($h->{ERROR} && $type == SRV) {
		$rcode = SERVFAIL;
		goto bad;
	}

	# subordinate error

	if ($h->{SERROR} && $type != SRV) {
		$rcode = SERVFAIL;
		goto bad;
	}

	if ($name eq '_http._tcp.example.net') {
		if ($type == SRV && $h->{SRV}) {
			map { push @rdata, rd_srv($ttl, (split ' ', $_)) }
				@{$h->{SRV}};
		}

		my $cname = defined $h->{CNAME} ? $h->{CNAME} : 0;
		if ($cname) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, "alias", 0xc00c + length("_http._tcp "));
		}

	} elsif ($name eq '_http._tcp.trunc.example.net' && $type == SRV) {
		push @rdata, $tcp
			? rd_srv($ttl, 1, 1, $port, 'tcp.example.net')
			: rd_srv($ttl, 1, 1, $port, 'example.net');

		$hdr |= 0x0300 if $name eq '_http._tcp.trunc.example.net'
			and !$tcp;

	} elsif ($name eq 'example.net' || $name eq 'tcp.example.net') {
		if ($type == A && $h->{A}) {
			map { push @rdata, rd_addr($ttl, $_) } @{$h->{A}};
		}
		if ($type == AAAA && $h->{AAAA}) {
			map { push @rdata, rd_addr6($ttl, $_) } @{$h->{AAAA}};
		}
		my $cname = defined $h->{CNAME} ? $h->{CNAME} : 0;
		if ($cname) {
			push @rdata, pack("n3N nCa5n", 0xc00c, CNAME, IN, $ttl,
				8, 5, $cname, 0xc00c);
		}

	} elsif ($name eq 'alias.example.net') {
		if ($type == SRV) {
			push @rdata, rd_srv($ttl, 1, 5, $port, 'example.net');
		}
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.203');
		}
	}

bad:

	Test::Nginx::log_core('||', "DNS: $name $type $rcode");

	$$cnt++ if $type == SRV || keys %$h;

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_srv {
	my ($ttl, $pri, $w, $port, $name) = @_;
	my @rdname = split /\./, $name;
	my $rdlen = length(join '', @rdname) + @rdname + 7;	# pri w port x

	pack 'n3N n n3 (C/a*)* x',
		0xc00c, SRV, IN, $ttl, $rdlen, $pri, $w, $port, @rdname;
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
	my ($port, $control_port, $t, %extra) = @_;
	my ($data, $recv_data, $h);

	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	my $control = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . $control_port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($socket, $control);
	my $tcp = 0;

	if ($extra{tcp}) {
		$tcp = port(8982, socket => 1);
		$sel->add($tcp);
	}

	local $SIG{PIPE} = 'IGNORE';

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;
	my $cnt = 0;

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($control == $fh || $tcp == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif ($socket == $fh) {
				$fh->recv($recv_data, 65536);
				$data = reply_handler($recv_data, $h, \$cnt);
				$fh->send($data);

			} elsif ($fh->sockport() == $control_port) {
				$h = process_name($fh, $cnt);
				$sel->remove($fh);
				$fh->close;

			} elsif ($fh->sockport() == $port) {
				$fh->recv($recv_data, 65536);
				unless (length $recv_data) {
					$sel->remove($fh);
					$fh->close;
					next;
				}

again:
				my $len = unpack("n", $recv_data);
				my $data = substr $recv_data, 2, $len;
				$data = reply_handler($data, $h, \$cnt, 1);
				$data = pack("n", length $data) . $data;
				$fh->send($data);
				$recv_data = substr $recv_data, 2 + $len;
				goto again if length $recv_data;
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
	$headers =~ /X-AAAA: (.*)$/m;
	map { push @{$h{AAAA}}, $_ } split(/ /, $1);
	$headers =~ /X-SRV: (.*)$/m;
	map { push @{$h{SRV}}, $_ } split(/;/, $1);
	$headers =~ /X-CNAME: (.+)$/m and $h{CNAME} = $1;
	$headers =~ /X-ERROR: (.+)$/m and $h{ERROR} = $1;
	$headers =~ /X-SERROR: (.+)$/m and $h{SERROR} = $1;

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
