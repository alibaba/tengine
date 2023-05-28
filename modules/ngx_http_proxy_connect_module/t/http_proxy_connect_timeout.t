#!/usr/bin/perl

# Copyright (C) 2010-2013 Alibaba Group Holding Limited

# Tests for connect method support.

###############################################################################

use warnings;
use strict;

use Test::More;
use Time::HiRes;
# use Test::Simple 'no_plan';
use Test::Nginx::Stream qw/ stream /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Net::DNS::Nameserver;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(16);

###############################################################################

my $nginx_conf = <<'EOF';
%%TEST_GLOBALS%%
daemon         off;
events { }

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable
    # directive "lua_package_path". For more details, see:
    #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    log_format connect '$remote_addr - $remote_user [$time_local] "$request" '
                       '$status $body_bytes_sent var:$connect_host-$connect_port-$connect_addr '
                       ' c:$proxy_connect_connect_timeout,r:$proxy_connect_data_timeout';

    access_log %%TESTDIR%%/connect.log connect;
    error_log %%TESTDIR%%/connect_error.log error;

    resolver 127.0.0.1:%%PORT_8981_UDP%% ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # forward proxy for CONNECT method
        proxy_connect;
        proxy_connect_allow all;
        proxy_connect_connect_timeout 10s;
        proxy_connect_data_timeout 10s;

        set $proxy_connect_connect_timeout  "101ms";
        set $proxy_connect_data_timeout     "103ms";

        if ($host = "test-connect-timeout.com") {
            set $proxy_connect_connect_timeout "1ms";
        }
        if ($host = "test-read-timeout.com") {
            set $proxy_connect_connect_timeout  "3ms";
            set $proxy_connect_data_timeout     "1ms";
        }

        location / {
            proxy_pass http://127.0.0.01:8081;
        }
    }
}

EOF

$t->write_file_expand('nginx.conf', $nginx_conf);

eval {
    $t->run();
};

if ($@) {
    print("+ Retry new nginx conf: remove \"ipv6=off\"\n");

    $nginx_conf =~ s/ ipv6=off;/;/g;        # remove ipv6=off in resolver directive.
    $t->write_file_expand('nginx.conf', $nginx_conf);
    $t->run();
}

$t->run_daemon(\&dns_daemon, port(8981), $t);
$t->waitforfile($t->testdir . '/' . port(8981));


TODO: {
    local $TODO = '# This case will pass, if connecting 8.8.8.8 timed out.';
    like(http_connect_request('test-connect-timeout.com', '8888', '/'), qr/504/, 'connect timed out: set $var');
    like($t->read_file('connect.log'),
         qr/"CONNECT test-connect-timeout.com:8888 HTTP\/1.1" 504 .+ c:1,r:103/,
        'connect timed out log: get $var & status=504');
    like($t->read_file('connect_error.log'),
         qr/proxy_connect: upstream connect timed out \(peer:8\.8\.8\.8:8888\) while connecting to upstream/,
        'connect timed out error log');
}

http_connect_request('test-read-timeout.com', '8888', '/');

# test reading variables of $proxy_connect_*_timeout
like($t->read_file('connect.log'),
     qr/"CONNECT test-connect-timeout.com:8888 HTTP\/1.1" ... .+ c:1,r:103/,
     'connect timed out log: get $var');
like($t->read_file('connect.log'),
     qr/"CONNECT test-read-timeout.com:8888 HTTP\/1.1" ... .+ c:3,r:1/,
     'connect/read timed out log: get $var');

$t->stop();

###############################################################################

$nginx_conf = <<'EOF';
%%TEST_GLOBALS%%
daemon         off;
events { }

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable
    # directive "lua_package_path". For more details, see:
    #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    log_format connect '$remote_addr - $remote_user [$time_local] "$request" '
                       '$status $body_bytes_sent var:$connect_host-$connect_port-$connect_addr '
                       ' c:$proxy_connect_connect_timeout,r:$proxy_connect_data_timeout';

    access_log %%TESTDIR%%/connect.log connect;
    error_log %%TESTDIR%%/connect_timeout_error.log debug;

    resolver 127.0.0.1:8085 ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # forward proxy for CONNECT method
        proxy_connect;
        proxy_connect_allow all;

        proxy_connect_data_timeout 10s;

        proxy_connect_address "127.0.0.1:8081";

        if ($http_x_timeout) {
            set $proxy_connect_data_timeout     $http_x_timeout;
        }

        location / {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}

EOF

$t->write_file_expand('nginx.conf', $nginx_conf);

$t->run_daemon(\&stream_daemon);

eval {
    $t->run();
};

if ($@) {
    print("+ Retry new nginx conf: remove \"ipv6=off\"\n");

    $nginx_conf =~ s/ ipv6=off;/;/g;        # remove ipv6=off in resolver directive.
    $t->write_file_expand('nginx.conf', $nginx_conf);
    $t->run();
}

print("+ try to waitforsocket...\n");
$t->waitforsocket('127.0.0.1:' . port(8081))
  or die "Can't start stream backend server";
print("+ try to waitforsocket...done\n");

# test time out of data proxying ( proxy_connect_data_timeout)
my $str = '1234567890' x 10 . 'F';
my $length = length($str);
my $sport =  port(8081);
my $s;

# test: timeout expired or not

$s = stream('127.0.0.1:' . port(8080));

like($s->io(<<EOF, read_timeout => 0.5), qr/200 Connection Established/, "establish CONNECT tunnel");
CONNECT 127.0.0.1:$sport HTTP/1.1
Host: stream
X-Timeout: 1000ms

EOF

my $i;
for ($i = 0; $i < 8; $i++) {
    my $ms = $i/10;
    Time::HiRes::sleep($ms);    # < timeout
    is($s->io($str, length => $length), $str,
       "timeout not expired, then sleep $ms s");
}

# check log
#2022/11/29 13:49:28 [info] 1746#0: *3 proxy_connect: connection timed out (110: Connection timed out) while proxying connection, client: 127.0.0.1, server: localhost, request: "CONNECT 127.0.0.1:8081 HTTP/1.1", host: "stream"
unlike($t->read_file('connect_timeout_error.log'),
     qr/proxy_connect: connection timed out .* "CONNECT .*", host: "stream"/,
     'get log: not timed out');

Time::HiRes::sleep(1.2);    # > timeout
like($t->read_file('connect_timeout_error.log'),
     qr/proxy_connect: connection timed out .* "CONNECT .*", host: "stream"/,
     'get log: timed out');

$t->stop();

###############################################################################


sub http_connect_request {
    my ($host, $port, $url) = @_;
    my $r = http_connect($host, $port, <<EOF);
GET $url HTTP/1.0
Host: $host
Connection: close

EOF
    return $r
}

sub http_connect($;%) {
    my ($host, $port, $request, %extra) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(2);
        my $s = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => '127.0.0.1:8080'
        );
        $s->print(<<EOF);
CONNECT $host:$port HTTP/1.1
Host: $host

EOF
        select undef, undef, undef, $extra{sleep} if $extra{sleep};
        return '' if $extra{aborted};
        my $n = $s->sysread($reply, 65536);
        return unless $n;
        if ($reply !~ /HTTP\/1\.[01] 200 Connection Established\r\nProxy-agent: .+\r\n\r\n/) {
            return $reply;
        }
        log_out($request);
        $s->print($request);
        local $/;
        select undef, undef, undef, $extra{sleep} if $extra{sleep};
        return '' if $extra{aborted};
        $reply = $s->getline();
        alarm(0);
    };
    alarm(0);
    if ($@) {
        log_in("died: $@");
        return undef;
    }
    log_in($reply);
    return $reply;
}

# --- DNS Server ---

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

	if (($name eq 'test-connect-timeout.com') || 
            ($name eq 'test-read-timeout.com')) 
        {
		if ($type == A) {
			push @rdata, rd_addr($ttl, '8.8.8.8');
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

################################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

        print("+ stream daemon started.\n");

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($server == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

        log2i("$client $buffer");
        $client->syswrite($buffer);
        return 0;

        log2i("$client $buffer");

	my $close = $buffer =~ /F/;

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $close;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }
##############################################################################
