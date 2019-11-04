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

# --- init DNS server ---

my $bind_pid;
my $bind_server_port = 18085;

# SRV record, not used
my %route_map;

# A record
my %aroute_map = (
    'www.test-a.com' => [[300, "127.0.0.1"]],
    'www.test-b.com' => [[300, "127.0.0.1"]],
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

    log_format connect '$remote_addr - $remote_user [$time_local] "$request" '
                       '$status $body_bytes_sent var:$connect_host-$connect_port-$connect_addr';

    access_log %%TESTDIR%%/connect.log connect;

    resolver 127.0.0.1:18085 ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen  8081;
        listen  8082;   # address.com
        listen  8083;   # bind.conm
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
        proxy_connect_read_timeout 10s;
        proxy_connect_send_timeout 10s;
        proxy_connect_send_lowat 0;
        proxy_connect_address $proxy_remote_address;
        proxy_connect_bind $proxy_local_address;

        if ($host = "address.com") {
            set $proxy_remote_address "127.0.0.1:8082";
        }

        if ($host = "bind.com") {
            set $proxy_remote_address "127.0.0.1:8083";
            set $proxy_local_address "127.0.0.1";   # NOTE that we cannot bind 127.0.0.3 in mac os x.
        }

        if ($host = "proxy-remote-address-resolve-domain.com") {
            set $proxy_remote_address "www.test-a.com:8081";
        }

        location / {
            proxy_pass http://127.0.0.1:8081;
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
like(http_connect_request('forbidden.example.com', '8080', '/'), qr/400 Bad Request/, 'forbid CONNECT request without proxy_connect command enabled');

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

    access_log off;

    server {
        listen  8082;
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

        proxy_connect_address 127.0.0.1:8082;

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
        $rcode = "NXDOMAIN";
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
        $s and close($s) || die 'can not connect to DNS server';

        print "+ DNS server: working\n";
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
