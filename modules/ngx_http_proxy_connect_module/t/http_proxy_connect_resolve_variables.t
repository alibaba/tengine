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

my $t = Test::Nginx->new()->has(qw/http proxy/); #->plan(12);

###############################################################################

my $test_enable_rewrite_phase = 1;

if (defined $ENV{TEST_DISABLE_REWRITE_PHASE}) {
    $test_enable_rewrite_phase = 0;
}

print("+ test_enable_rewrite_phase: $test_enable_rewrite_phase\n");

plan(skip_all => 'No rewrite phase enabled') if ($test_enable_rewrite_phase == 0);

# --- init DNS server ---

my $bind_pid;
my $bind_server_port = 18085;

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

start_bind();

# --- end ---

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

    resolver 127.0.0.1:18085 ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

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


# --- stop DNS server ---

stop_bind();

done_testing();

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
    my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
    my ($rcode, @ans, @auth, @add);
    # print("DNS reply: receive query=$qname, $qclass, $qtype, $peerhost, $query, $conn\n");

    if ($qtype eq "SRV" && exists($route_map{$qname})) {
        my @records = @{$route_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $weight, $priority, $port, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $priority $weight $port $origin_addr");
            push @ans, $rr;
            # print("DNS reply: $qname $ttl $qclass $qtype $origin_addr\n");
        }

        $rcode = "NOERROR";
    } elsif (($qtype eq "A") && exists($aroute_map{$qname})) {
        my @records = @{$aroute_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $origin_addr");
            push @ans, $rr;
            # print("DNS reply: $qname $ttl $qclass $qtype $origin_addr\n");
        }

        $rcode = "NOERROR";
    } elsif (($qtype eq "AAAA") && exists($aaaaroute_map{$qname})) {
        my @records = @{$aaaaroute_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $origin_addr");
            push @ans, $rr;
            # print("DNS reply: $qname $ttl $qclass $qtype $origin_addr\n");
        }

        $rcode = "NOERROR";
    } else {
        #$rcode = "NXDOMAIN";
        $rcode = "NOERROR";
    }

    # mark the answer as authoritative (by setting the 'aa' flag)
    my $headermask = { ra => 1 };

    # specify EDNS options  { option => value }
    my $optionmask = { };

    return ($rcode, \@ans, \@auth, \@add, $headermask, $optionmask);
}

sub bind_daemon {
    my $ns = new Net::DNS::Nameserver(
        LocalAddr        => ['127.0.0.1'],
        LocalPort        => $bind_server_port,
        ReplyHandler     => \&reply_handler,
        Verbose          => 0, # Verbose = 1 to print debug info
        Truncate         => 0
    ) || die "[D] DNS server: couldn't create nameserver object\n";

    $ns->main_loop;
}

sub start_bind {
    if (defined $bind_server_port) {

        print "+ DNS server: try to bind server port: $bind_server_port\n";

        $t->run_daemon(\&bind_daemon);
        $bind_pid = pop @{$t->{_daemons}};

        print "+ DNS server: daemon pid: $bind_pid\n";

        my $s;
        my $i = 1;
        while (not $s) {
            $s = IO::Socket::INET->new(
                 Proto    => 'tcp',
                 PeerAddr => "127.0.0.1",
                 PeerPort => $bind_server_port
            );
            sleep 0.1;
            $i++ > 20 and last;
        }
        sleep 0.1;
        $s or die "cannot connect to DNS server";
        close($s) or die 'can not connect to DNS server';

        print "+ DNS server: working\n";

        END {
            print("+ try to stop\n");
            stop_bind();
        }
    }
}

sub stop_bind {
    if (defined $bind_pid) {
        # kill dns daemon
        kill $^O eq 'MSWin32' ? 15 : 'TERM', $bind_pid;
        wait;

        $bind_pid = undef;
        print ("+ DNS server: stop\n");
    }
}

###############################################################################
