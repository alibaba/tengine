#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for dynamic upstream configuration with re-resolvable servers.
# Ensure that dns updates are properly applied.

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
        server example.net:%%PORT_8080%% resolve max_fails=0;
    }

    # lower the retry timeout after empty reply
    resolver 127.0.0.1:%%PORT_8982_UDP%% valid=1s;
    # retry query shortly after DNS is started
    resolver_timeout 1s;

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location / {
            proxy_pass http://u/t;
            proxy_connect_timeout 50ms;
            add_header X-IP $upstream_addr;
            error_page 502 504 redirect;
        }

        location /2 {
            proxy_pass http://u/t;
            add_header X-IP $upstream_addr;
        }

        location /t { }
    }
}

EOF

port(8083);

$t->write_file('t', '');

$t->run_daemon(\&dns_daemon, $t)->waitforfile($t->testdir . '/' . port(8982));
$t->try_run('no resolve in upstream server')->plan(18);

###############################################################################

my ($r, @n);
my $p0 = port(8080);

update_name({A => '127.0.0.201'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A');
like($r, qr/127.0.0.201:$p0/, 'A 1');

# A changed

update_name({A => '127.0.0.202'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A changed');
like($r, qr/127.0.0.202:$p0/, 'A changed 1');

# 1 more A added

update_name({A => '127.0.0.201 127.0.0.202'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 2, 'A A');
like($r, qr/127.0.0.201:$p0/, 'A A 1');
like($r, qr/127.0.0.202:$p0/, 'A A 2');

# 1 A removed, 2 AAAA added

update_name({A => '127.0.0.201', AAAA => 'fe80::1 fe80::2'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 3, 'A AAAA AAAA responses');
like($r, qr/127.0.0.201:$p0/, 'A AAAA AAAA 1');
like($r, qr/\[fe80::1\]:$p0/, 'A AAAA AAAA 2');
like($r, qr/\[fe80::1\]:$p0/, 'A AAAA AAAA 3');

# all records removed

update_name();
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 0, 'empty response');

# A added after empty

update_name({A => '127.0.0.201'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'A added');
like($r, qr/127.0.0.201:$p0/, 'A added 1');

# changed to CNAME

update_name({CNAME => 'alias'}, 4);
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'CNAME');
like($r, qr/127.0.0.203:$p0/, 'CNAME 1');

# bad DNS reply should not affect existing upstream configuration

update_name({ERROR => 'SERVFAIL'});
$r = http_get('/');
is(@n = $r =~ /:$p0/g, 1, 'ERROR');
like($r, qr/127.0.0.203:$p0/, 'ERROR 1');
update_name({A => '127.0.0.1'});

###############################################################################

sub update_name {
	my ($name, $plan) = @_;

	$plan = 2 if !defined $plan;

	sub sock {
		IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:' . port(8083)
		)
			or die "Can't connect to nginx: $!\n";
	}

	$name->{A} = '' unless $name->{A};
	$name->{AAAA} = '' unless $name->{AAAA};
	$name->{CNAME} = '' unless $name->{CNAME};
	$name->{ERROR} = '' unless $name->{ERROR};

	my $req =<<EOF;
GET / HTTP/1.0
Host: localhost
X-A: $name->{A}
X-AAAA: $name->{AAAA}
X-CNAME: $name->{CNAME}
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
	use constant CNAME	=> 5;
	use constant AAAA	=> 28;
	use constant DNAME	=> 39;
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

	if ($name eq 'example.net') {
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
		if ($type == A) {
			push @rdata, rd_addr($ttl, '127.0.0.203');
		}
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
	my ($t) = @_;
	my ($data, $recv_data, $h);

	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => port(8982),
		Proto=> 'udp',
	)
		or die "Can't create listening socket: $!\n";

	my $control = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:" . port(8083),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($socket, $control);

	local $SIG{PIPE} = 'IGNORE';

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . port(8982);
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
	$headers =~ /X-AAAA: (.*)$/m;
	map { push @{$h{AAAA}}, $_ } split(/ /, $1);
	$headers =~ /X-CNAME: (.*)$/m;
	$h{CNAME} = $1;
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
