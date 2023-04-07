#!/usr/bin/perl

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

my $t = Test::Nginx->new()->has(qw/http proxy lua/); #->plan(12);

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
    'set-response-header.com' => [[300, "127.0.0.1"]],
    'set-response-status.com' => [[300, "127.0.0.1"]],
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

$t->write_file_expand('nginx.conf', <<'EOF');

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

    access_log off;

    resolver 127.0.0.1:18085 ipv6=off;      # NOTE: cannot connect ipv6 address ::1 in mac os x.

    server {
        listen       127.0.0.1:8080;
        proxy_connect;
        proxy_connect_allow all;

        rewrite_by_lua '
            if ngx.var.host == "set-response-header.com" then
                ngx.var.proxy_connect_response =
                  string.format("HTTP/1.1 200\\r\\nProxy-agent: nginx/%s\\r\\n\\r\\n", ngx.var.nginx_version)
            end
        ';
    }

    server {
        listen  8081;
        location / {
            return 200 "backend";
        }
    }
}

EOF

# test $proxy_connect_response variable via lua-nginx-module

$t->run();

if ($test_enable_rewrite_phase) {
    like(http_connect_request('set-response-header.com', '8081', '/'), qr/Proxy-agent: nginx\/[\d.]+\r/, 'modify Proxy-agent to nginx version');
}

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
        $s or die "cannot connect to DNS server";
        close($s) or die 'can not connect to DNS server';

        print "+ DNS server: working\n";

        END {
            print("+ try to stop $bind_pid\n");
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
