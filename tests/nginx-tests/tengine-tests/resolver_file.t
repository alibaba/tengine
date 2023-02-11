#!/usr/bin/perl

# (C) Xiaochen Wang

###############################################################################

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Net::DNS::Nameserver;


###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'must be root') if $> != 0;

sub http_get_host($;$;%) {
    my ($url, $host, %extra) = @_;
    return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: $host

EOF
}

my $t = Test::Nginx->new()->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv.conf;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host:8082;
        }
    }

    server {
        listen      127.0.0.1:8082;
        return 200 "resolved success";
    }
}

EOF

$t->write_file_expand('resolv.conf', <<'EOF');
nameserver 127.0.0.1
EOF

# --- init DNS server ---
my $bind_pid;
my $bind_server_port = 53;
# SRV record, not used
my %route_map;
# A record
my %aroute_map = (
    'test.com' => [[300, "127.0.0.1"]],
);
# AAAA record (ipv6)
my %aaaaroute_map;

start_bind($t);
# --- end ---

my $test_dir = $t->testdir();
$t->run();


like(http_get_host("/", "test.com"),
     qr/resolved success/,
     "auto load $test_dir/resolv.conf");

$t->stop();
stop_bind();

# --- DNS Server ---

sub reply_handler {
    my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
    my ($rcode, @ans, @auth, @add);

    if ($qtype eq "SRV" && exists($route_map{$qname})) {
        my @records = @{$route_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $weight, $priority, $port, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $priority $weight $port $origin_addr");
            push @ans, $rr;
        }

        $rcode = "NOERROR";
    } elsif (($qtype eq "A") && exists($aroute_map{$qname})) {
        my @records = @{$aroute_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $origin_addr");
            push @ans, $rr;
        }

        $rcode = "NOERROR";
    } elsif (($qtype eq "AAAA") && exists($aaaaroute_map{$qname})) {
        my @records = @{$aaaaroute_map{$qname}};
        for (my $i = 0; $i < scalar(@records); $i++) {
            my ($ttl, $origin_addr) = @{$records[$i]};
            my $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $origin_addr");
            push @ans, $rr;
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
    my $ns = Net::DNS::Nameserver->new(
        LocalAddr        => ['127.0.0.1'],
        LocalPort        => $bind_server_port,
        ReplyHandler     => \&reply_handler,
        Verbose          => 0, # Verbose = 1 to print debug info
        Truncate         => 0
    ) or die "[D] DNS server: couldn't create nameserver object\n";

    $ns->main_loop;
}

sub start_bind {
    # cannot refer $t in start_bind directly, otherwise NGINX::TEST will fail
    my ($nt) = @_;
    if (defined $bind_server_port) {

        print("+ DNS server: try to bind server port: $bind_server_port\n");

        $nt->run_daemon(\&bind_daemon);
        $bind_pid = pop @{$nt->{_daemons}};

        print("+ DNS server: daemon pid: $bind_pid\n");

        END {
            stop_bind();
        }

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

        print("+ DNS server: working\n");
    }
}

sub stop_bind {
    if (defined $bind_pid) {
        # kill dns daemon
        kill $^O eq 'MSWin32' ? 15 : 'TERM', $bind_pid;
        wait;

        $bind_pid = undef;
        print("+ DNS server: stop\n");
    } else {
        print("+ DNS server has been stopped\n");
    }
}
