#!/usr/bin/perl

# Copyright (C) 2010-2013 Alibaba Group Holding Limited

# Tests for connect method support.

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

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(22);

###############################################################################

my $test_enable_rewrite_phase = 1;

if (defined $ENV{TEST_DISABLE_REWRITE_PHASE}) {
    $test_enable_rewrite_phase = 0;
}

print("+ test_enable_rewrite_phase: $test_enable_rewrite_phase\n");

# --- init DNS server ---

# SRV record, not used
my %route_map;

# A record
my %aroute_map = (
    'www.test-a.com' => [[300, "127.0.0.1"]],
    'www.test-b.com' => [[300, "127.0.0.1"]],
    'get-default-response.com' => [[300, "127.0.0.1"]],
    'set-response-header.com' => [[300, "127.0.0.1"]],
    'set-response-status.com' => [[300, "127.0.0.1"]],
);

###############################################################################

my $nginx_conf = <<'EOF';

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           # directive "lua_package_path". For more details, see:              #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    log_format connect '$remote_addr - $remote_user [$time_local] "$request" '
                       '$status $body_bytes_sent var:$connect_host-$connect_port-$connect_addr';

    access_log %%TESTDIR%%/connect.log connect;

    resolver 127.0.0.1:%%PORT_8981_UDP%% ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen  127.0.0.1:8081;
        listen  127.0.0.1:8082;   # address.com
        listen  127.0.0.1:8083;   # bind.conm
        server_name server_8081;
        access_log off;
        location / {
            return 200 "backend server: addr:$remote_addr port:$server_port host:$host\n";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        set $proxy_remote_address "";
        set $proxy_local_address "";
        # forward proxy for CONNECT method
        proxy_connect;
        proxy_connect_allow 443 80 8081;
        proxy_connect_connect_timeout 10s;
        proxy_connect_data_timeout 10s;
        proxy_connect_address $proxy_remote_address;
        proxy_connect_bind $proxy_local_address;

        if ($host = "address.com") {
            set $proxy_remote_address "127.0.0.01:8082";
        }

        if ($host = "bind.com") {
            set $proxy_remote_address "127.0.0.01:8083";
            set $proxy_local_address "127.0.0.1";   # NOTE that we cannot bind 127.0.0.3 in mac os x.
        }

        if ($host = "proxy-remote-address-resolve-domain.com") {
            set $proxy_remote_address "www.test-a.com:8081";
        }

        location / {
            proxy_pass http://127.0.0.01:8081;
        }

        location = /hello {
            return 200 "world";
        }

        # used to output connect.log
        location = /connect.log {
            access_log off;
            root %%TESTDIR%%/;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  forbidden.example.com;

        # It will forbid CONNECT request without proxy_connect command enabled.

        return 200;
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

like(http_connect_request('127.0.0.1', '8081', '/'), qr/backend server/, '200 Connection Established');
like(http_connect_request('www.test-a.com', '8081', '/'), qr/host:www\.test-a\.com/, '200 Connection Established server name');
like(http_connect_request('www.test-b.com', '8081', '/'), qr/host:www\.test-b\.com/, '200 Connection Established server name');
like(http_connect_request('www.no-dns-reply.com', '80', '/'), qr/502/, '200 Connection Established server name');
like(http_connect_request('127.0.0.1', '9999', '/'), qr/403/, '200 Connection Established not allowed port');
like(http_get('/'), qr/backend server/, 'Get method: proxy_pass');
like(http_get('/hello'), qr/world/, 'Get method: return 200');
like(http_connect_request('forbidden.example.com', '8080', '/'), qr/405 Not Allowed/, 'forbid CONNECT request without proxy_connect command enabled');

# proxy_remote_address directive supports dynamic domain resolving.
like(http_connect_request('proxy-remote-address-resolve-domain.com', '8081', '/'),
     qr/host:proxy-remote-address-resolve-domain\.com/,
     'proxy_remote_address supports dynamic domain resovling');

if ($test_enable_rewrite_phase) {
    like(http_connect_request('address.com', '8081', '/'), qr/backend server: addr:127.0.0.1 port:8082/, 'set remote address');
    like(http_connect_request('bind.com', '8081', '/'), qr/backend server: addr:127.0.0.1 port:8083/, 'set local address and remote address');
}


# test $connect_host, $connect_port
my $log = http_get('/connect.log');
like($log, qr/CONNECT 127\.0\.0\.1:8081.*var:127\.0\.0\.1-8081-127\.0\.0\.1:8081/, '$connect_host, $connect_port, $connect_addr');
like($log, qr/CONNECT www\.no-dns-reply\.com:80.*var:www\.no-dns-reply\.com-80--/, 'dns resolver fail');

$t->stop();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           # directive "lua_package_path". For more details, see:              #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    access_log off;

    server {
        listen  127.0.0.1:8082;
        location / {
            return 200 "backend server: $remote_addr $server_port\n";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # forward proxy for CONNECT method

        proxy_connect;
        proxy_connect_allow all;

        proxy_connect_address 127.0.0.01:8082;

        if ($host = "if-return-skip.com") {
            return 200 "if-return\n";
        }

        return 200 "skip proxy connect: $host,$uri,$request_uri,$args\n";
    }
}

EOF


$t->run();
if ($test_enable_rewrite_phase) {
    like(http_connect_request('address.com', '8081', '/'), qr/skip proxy connect/, 'skip proxy connect module without rewrite phase enabled');
    like(http_connect_request('if-return-skip.com', '8081', '/'), qr/if-return/, 'skip proxy connect module without rewrite phase enabled: if/return');
} else {
    like(http_connect_request('address.com', '8081', '/'), qr/backend server: 127.0.0.1 8082/, 'set remote address without nginx variable');
}
$t->stop();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           # directive "lua_package_path". For more details, see:              #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    access_log off;

    server {
        listen       127.0.0.1:8080;
        proxy_connect;
        proxy_connect_allow all;
    }
}

EOF


$t->run();

$t->write_file('test.html', 'test page');

like(http_get('/test.html'), qr/test page/, '200 for default root directive without location {}');
like(http_get('/404'), qr/ 404 Not Found/, '404 for default root directive without location {}');

$t->stop();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           # directive "lua_package_path". For more details, see:              #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    access_log off;

    resolver 127.0.0.1:%%PORT_8981_UDP%% ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen       127.0.0.1:8080;
        proxy_connect;
        proxy_connect_allow all;

        if ($host = "get-default-response.com") {
            return 403 "|$proxy_connect_response|";
        }

        if ($host = "set-response-header.com") {
            set $proxy_connect_response "HTTP/1.1 200\r\nFoo: bar\r\n\r\n";
        }

        if ($host = "set-response-status.com") {
            set $proxy_connect_response "HTTP/1.1 403\r\n\r\n";
        }
    }

    server {
        listen  8081;
        location / {
            return 200 "backend";
        }
    }
}

EOF

# test $proxy_connect_response variable

$t->run();

if ($test_enable_rewrite_phase) {
    like(http_connect_request('www.test-a.com', '8081', '/'), qr/OK/, 'nothing changed with CONNECT response');

    like(http_connect_request_raw('get-default-response.com', '8081', '/'),
         qr/\|HTTP\/1\.1 200 Connection Established\r\nProxy-agent: nginx\r\n\r\n\|/,
        'get default CONNECT response');

    like(http_connect_request('set-response-header.com', '8081', '/'), qr/Foo: bar\r/, 'added header "Foo: bar" to CONNECT response');
    like(http_connect_request('set-response-status.com', '8081', '/'), qr/HTTP\/1.1 403/, 'change CONNECT response status');
}

$t->stop();

###############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    #LUA_PACKAGE_PATH
    # If you build nginx with lua-nginx-module, please enable           # directive "lua_package_path". For more details, see:              #  https://github.com/openresty/lua-nginx-module#installation
    #lua_package_path "/path/to/lib/lua/?.lua;;";

    access_log off;

    resolver 127.0.0.1:%%PORT_8981_UDP%% ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen       127.0.0.1:8080;
        proxy_connect;
        proxy_connect_allow all;

        proxy_connect_response "HTTP/1.1 200 Connection Established\r\nProxy-agent: nginx\r\nX-Proxy-Connected-Addr: $connect_addr\r\n\r\n";
    }

    server {
        listen  8081;
        location / {
            return 200 "backend";
        }
    }
}

EOF

# test proxy_connect_response directive

$t->run();

if ($test_enable_rewrite_phase) {
    like(http_connect_request('set-response-header.com', '8081', '/'), qr/X-Proxy-Connected-Addr: 127.0.0.1:8081\r/, 'added header "Foo: bar" to CONNECT response');
}

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

sub http_connect_request_raw {
    my ($host, $port, $url) = @_;
    my $r = http_connect_raw($host, $port, <<EOF);
GET $url HTTP/1.0
Host: $host
Connection: close

EOF
    return $r
}

sub http_connect_raw($;%) {
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
CONNECT $host:$port HTTP/1.0
Host: $host

EOF
        select undef, undef, undef, $extra{sleep} if $extra{sleep};
        return '' if $extra{aborted};
        my $n = $s->sysread($reply, 65536);
        return unless $n;
        return $reply;

        # ignore data flow over CONNECT tunnel
        #log_out($request);
        #$s->print($request);
        #local $/;
        #select undef, undef, undef, $extra{sleep} if $extra{sleep};
        #return '' if $extra{aborted};
        #$reply =  $s->getline();
        #alarm(0);
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
