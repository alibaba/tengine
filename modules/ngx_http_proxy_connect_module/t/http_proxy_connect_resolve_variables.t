#!/usr/bin/perl

# Copyright (C) 2010-2013 Alibaba Group Holding Limited

# Tests for connect method support.

###############################################################################

use warnings;
use strict;

use Test::More;
# use Test::Simple 'no_plan';

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Net::DNS::Nameserver;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(14);

###############################################################################

my $test_enable_rewrite_phase = 1;

if (defined $ENV{TEST_DISABLE_REWRITE_PHASE}) {
    $test_enable_rewrite_phase = 0;
}

print("+ test_enable_rewrite_phase: $test_enable_rewrite_phase\n");

plan(skip_all => 'No rewrite phase enabled') if ($test_enable_rewrite_phase == 0);

# --- init DNS server ---

# SRV record, not used
my %route_map;

# A record
my %aroute_map = (
    'test-connect-timeout.com' => [[300, "8.8.8.8"]],
    'test-read-timeout.com' => [[300, "8.8.8.8"]],
);

# AAAA record (ipv6)
my %aaaaroute_map;
# my %aaaaroute_map = (
#     'www.test-a.com' => [[300, "[::1]"]],
#     'www.test-b.com' => [[300, "[::1]"]],
#     #'www.test-a.com' => [[300, "127.0.0.1"]],
#     #'www.test-b.com' => [[300, "127.0.0.1"]],
# );

###############################################################################

my $nginx_conf = <<'EOF';

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           
    # directive "lua_package_path". For more details, see:              
    #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

#    lua_load_resty_core off;

    log_format connect '$remote_addr - $remote_user [$time_local] "$request" '
                       '$status $body_bytes_sent var:$connect_host-$connect_port-$connect_addr '
                       'resolve:$proxy_connect_resolve_time,'
                       'connect:$proxy_connect_connect_time,'
                       'fbt:$proxy_connect_first_byte_time,';

    access_log %%TESTDIR%%/connect.log connect;
    error_log %%TESTDIR%%/connect_error.log info;

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

        if ($uri = "/200") {
            return 200;
        }

        if ($host = "test-connect-timeout.com") {
            set $proxy_connect_connect_timeout "1ms";
        }
        if ($host = "test-read-timeout.com") {
            set $proxy_connect_connect_timeout  "3ms";
            set $proxy_connect_data_timeout     "1ms";
        }

        if ($request ~ "127.0.0.1:8082") {
            # must be larger than 1s (server 8082 lua sleep(1s))
            set $proxy_connect_data_timeout "1200ms";
        }

        if ($request ~ "127.0.0.1:8083") {
            # must be larger than 0.5s (server 8082 lua sleep(0.5s))
            set $proxy_connect_data_timeout "700ms";
        }

        if ($request ~ "127.0.0.01:8082") {
            # must be less than 1s (server 8082 lua sleep(1s))
            set $proxy_connect_data_timeout "800ms";
        }

        if ($request ~ "127.0.0.01:8083") {
            # must be less than 0.5s (server 8082 lua sleep(1s))
            set $proxy_connect_data_timeout "300ms";
        }

        location / {
            proxy_pass http://127.0.0.01:8081;
        }
    }

    server {
        listen 8081;
        access_log off;
        return 200 "8081 server";
    }

    # for $proxy_connect_first_byte_time testing
    server {
        access_log off;
        listen 8082;

        rewrite_by_lua '
            ngx.sleep(1)
            ngx.say("8082 server fbt")
            ngx.exit(ngx.HTTP_OK)
        ';

    }
    server {
        access_log off;
        listen 8083;
        rewrite_by_lua '
            ngx.sleep(0.5)
            ngx.say("8083 server fbt")
            ngx.exit(ngx.HTTP_OK)
        ';

    }

}

EOF

$t->write_file_expand('nginx.conf', $nginx_conf);

$t->run_daemon(\&dns_daemon, port(8981), $t);
$t->waitforfile($t->testdir . '/' . port(8981));

eval {
    $t->run();
};

if ($@) {
    print("+ Retry new nginx conf: remove \"ipv6=off\"\n");

    $nginx_conf =~ s/ ipv6=off;/;/g;        # remove ipv6=off in resolver directive.
    $t->write_file_expand('nginx.conf', $nginx_conf);
    $t->run();
}

#if (not $test_enable_rewrite_phase) {
#  exit
#}

TODO: {
    # $proxy_connect_connect_time has value, $proxy_connect_connect_time is "-"
    local $TODO = '# This case will pass, if connecting 8.8.8.8 timed out.';
    http_connect_request('test-connect-timeout.com', '8888', '/');
    like($t->read_file('connect.log'),
         qr/"CONNECT test-connect-timeout.com:8888 HTTP\/1.1" 504 .+ resolve:\d+\.\d+,connect:-/,
        'connect timed out log: get $var & status=504');
    like($t->read_file('connect_error.log'),
         qr/proxy_connect: upstream connect timed out \(peer:8\.8\.8\.8:8888\) while connecting to upstream/,
        'connect timed out error log');
}

# Both $proxy_connect_resolve_time & $proxy_connect_connect_time are empty string.
http_get('/200');
like($t->read_file('connect.log'),
     qr/GET \/200.*resolve:,connect:,/,
     'For GET request, both $proxy_connect_resolve_time & $proxy_connect_connect_time are empty string');


# Both $proxy_connect_resolve_time & $proxy_connect_connect_time have value.
http_connect_request('127.0.0.1', '8081', '/');
like($t->read_file('connect.log'),
     qr/"CONNECT 127.0.0.1:8081 HTTP\/1.1" 200 .+ resolve:0\.\d+,connect:0\.\d+,/,
     'For CONNECT request, test both $proxy_connect_resolve_time & $proxy_connect_connect_time');

# DNS resolving fails. Both $proxy_connect_resolve_time & $proxy_connect_connect_time are "-".
http_connect_request('non-existent-domain.com', '8081', '/');
like($t->read_file('connect.log'),
     qr/"CONNECT non-existent-domain.com:8081 HTTP\/1.1" 502 .+ resolve:-,connect:-,/,
     'For CONNECT request, test both $proxy_connect_resolve_time & $proxy_connect_connect_time');
like($t->read_file('connect_error.log'),
     qr/proxy_connect: non-existent-domain.com could not be resolved .+Host not found/,
     'test error.log for 502 respsone');

# test first byte time
# fbt:~1s
my $r;
$r = http_connect_request('127.0.0.1', '8082', '/');
like($r, qr/8082 server fbt/, "test first byte time: 1s, receive response from backend server");
like($t->read_file('connect.log'),
     qr/"CONNECT 127.0.0.1:8082 HTTP\/1.1" 200 .+ resolve:0\....,connect:0\....,fbt:1\....,/,
     'test first byte time: 1s');

# fbt:~0.5s
$r = http_connect_request('127.0.0.1', '8083', '/');
like($r, qr/8083 server fbt/, "test first byte time: 0.5s, receive response from backend server");

like($t->read_file('connect.log'),
     qr/"CONNECT 127.0.0.1:8083 HTTP\/1.1" 200 .+ resolve:0\....,connect:0\....,fbt:0\.5..,/,
     'test first byte time: 0.5s');

# test timeout
$t->write_file('connect_error.log', "");
$r = http_connect_request('127.0.0.01', '8082', '/');
is($r, "", "test first byte time: 1s, timeout");
#'2022/11/24 20:51:13 [info] 15239#0: *15 proxy_connect: connection timed out (110: Connection timed out) while proxying connection, client: 127.0.0.1, server: localhost, request: "CONNECT 127.0.0.01:8082 HTTP/1.1", host: "127.0.0.01"
like($t->read_file('connect_error.log'),
     qr/\[info\].* proxy_connect: connection timed out.+ request: "CONNECT 127\.0\.0\.01:8082 HTTP\/..."/,
     'test first byte time: 1s, check timeout in error log');

$t->write_file('connect_error.log', "");
$r = http_connect_request('127.0.0.01', '8083', '/');
is($r, "", "test first byte time: 0.5s, timeout");
like($t->read_file('connect_error.log'),
     qr/\[info\].* proxy_connect: connection timed out.+ request: "CONNECT 127\.0\.0\.01:8083 HTTP\/..."/,
     'test first byte time: 1s, check timeout in error log');

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

###############################################################################

sub reply_handler {
	my ($recv_data, $port, $state, %extra) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant FORMERR	=> 1;
	use constant SERVFAIL	=> 2;
	use constant NXDOMAIN	=> 3;

	use constant A		=> 1;
	use constant CNAME	=> 5;
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

        if (($type == A) && exists($aroute_map{$name})) {

            my @records = @{$aroute_map{$name}};

            for (my $i = 0; $i < scalar(@records); $i++) {
                my ($ttl, $origin_addr) = @{$records[$i]};
                push @rdata, rd_addr($ttl, $origin_addr);

                #print("dns reply: $name $ttl $class $type $origin_addr\n");
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
	my ($port, $t, %extra) = @_;

        print("+ dns daemon: try to listen on 127.0.0.1:$port\n");

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($socket);
	my $tcp = 0;

	if ($extra{tcp}) {
		$tcp = port(8983, socket => 1);
		$sel->add($tcp);
	}

	local $SIG{PIPE} = 'IGNORE';

	# track number of relevant queries

	my %state = (
		cnamecnt	=> 0,
		twocnt		=> 0,
		ttlcnt		=> 0,
		ttl0cnt		=> 0,
		cttlcnt		=> 0,
		cttl2cnt	=> 0,
		manycnt		=> 0,
		casecnt		=> 0,
		idcnt		=> 0,
		fecnt		=> 0,
	);

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($tcp == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif ($socket == $fh) {
				$fh->recv($recv_data, 65536);
				$data = reply_handler($recv_data, $port,
					\%state);
				$fh->send($data);

			} else {
				$fh->recv($recv_data, 65536);
				unless (length $recv_data) {
					$sel->remove($fh);
					$fh->close;
					next;
				}

again:
				my $len = unpack("n", $recv_data);
				$data = substr $recv_data, 2, $len;
				$data = reply_handler($data, $port, \%state,
					tcp => 1);
				$data = pack("n", length $data) . $data;
				$fh->send($data);
				$recv_data = substr $recv_data, 2 + $len;
				goto again if length $recv_data;
			}
		}
	}
}

###############################################################################
