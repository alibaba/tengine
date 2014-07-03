#!/usr/bin/perl

# (C) Jason Liu

# Tests for dynamic resolve in proxy module.
#
# Usage: need to write one entry in /etc/hosts file to let
# nginx get started:
#     127.0.0.1 senginx.test
#
###############################################################################

use warnings;
use strict;
use v5.14;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Net::DNS::Nameserver;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(5);
my @server_addrs = ("127.0.0.1", "127.0.0.2", "127.0.0.3", "127.0.0.4");
my @domain_addrs = ("127.0.0.2");

my $ipv6 = $t->has_module("ipv6") ? "ipv6=off" : "";

$t->write_file_expand('nginx.conf', <<"EOF");

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    resolver 127.0.0.1:53530 valid=1s $ipv6;
    resolver_timeout 1s;

    upstream backend {
        server senginx.test:8081 fail_timeout=0s;

        server 127.0.0.4:8081 backup;
    }

    upstream backend-ka {
        server senginx.test:8082;

        keepalive 8;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /static {
            proxy_pass http://backend;
        }

        location / {
            proxy_pass http://backend dynamic_resolve;
        }

        location /stale {
            proxy_pass http://backend dynamic_resolve dynamic_fallback=stale;
        }

        location /next {
            proxy_pass http://backend dynamic_resolve dynamic_fallback=next;
        }

        location /shutdown {
            proxy_pass http://backend dynamic_resolve dynamic_fallback=shutdown;
        }
    }
}

EOF

foreach my $ip (@server_addrs) {
    $t->run_daemon(\&http_daemon, $ip);
}

$t->run_daemon(\&dns_server_daemon);
my $dns_pid = pop @{$t->{_daemons}};

$t->run();

###############################################################################

like(http_get('/static'), qr/127\.0\.0\.1/,
    'static resolved should be 127.0.0.1');

like(http_get('/'), qr/127\.0\.0\.2/,
    'http server should be 127.0.0.2');

# kill dns daemon
kill $^O eq 'MSWin32' ? 9 : 'TERM', $dns_pid;
wait;

# wait for dns cache to expire
sleep(2);

# peers should be 127.0.0.2 and 127.0.0.3
like(http_get('/stale'), qr/127\.0\.0\.1/,
    'stale http server should be 127.0.0.1, using initial result');

like(http_get('/shutdown'), qr/502 Bad Gateway/,
    'shutdown connection if dns query is failed');

like(http_get('/next'), qr/127\.0\.0\.4/, 'next upstream should be 127.0.0.4');

###############################################################################

sub http_daemon {
    my $addr = shift @_;
    my $server = IO::Socket::INET->new(
        Proto => 'tcp',
        LocalHost => "$addr:8081",
        Listen => 5,
        Reuse => 1
    ) or die "Can't create listening socket: $!\n";

    my $resp;

    for ($addr) {
        when ("127.0.0.1") {$resp = "from server 127.0.0.1";}
        when ("127.0.0.2") {$resp = "from server 127.0.0.2";}
        when ("127.0.0.3") {$resp = "from server 127.0.0.3";}
        when ("127.0.0.4") {$resp = "from server 127.0.0.4";}
    }

    while (my $client = $server->accept()) {
        $client->autoflush(1);

        my $headers = '';
        my $uri = '';

        while (<$client>) {
            $headers .= $_;
            last if (/^\x0d?\x0a?$/);
        }

        $uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

        if ($uri eq '/'
            or $uri eq '/static'
            or $uri eq '/next'
            or $uri eq '/stale'
            or $uri eq '/shutdown') {

            print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
            print $client "$resp" unless $headers =~ /^HEAD/i;
        } else {
            print $client <<"EOF";
HTTP/1.1 404 Not Found
Connection: close

Oops, '$uri' not found
EOF
        }

        close $client;
    }
}


sub reply_handler {
    my ($qname, $qclass, $qtype, $peerhost,$query,$conn) = @_;
    my ($rcode, $rr, $ttl, $rdata, @ans, @auth, @add,);

    #print "Received query from $peerhost to ". $conn->{sockhost}. "\n";
    $query->print;

    if ($qtype ne "A") {
        $rcode = "NXDOMAIN";
        return ($rcode, \@ans, \@auth, \@add, { aa => 1 });
    }

    if ($qname eq "senginx.test") {
        foreach my $ip (@domain_addrs) {
            ($ttl, $rdata) = (3600, $ip);
            $rr = new Net::DNS::RR("$qname $ttl $qclass $qtype $rdata");
            push @ans, $rr;
        }

        $rcode = "NOERROR";
    } else {
        $rcode = "NXDOMAIN";
    }

    return ($rcode, \@ans, \@auth, \@add, { aa => 1 });
}

sub dns_server_daemon {
    my $ns = new Net::DNS::Nameserver(
        LocalPort    => 53530,
        ReplyHandler => \&reply_handler,
        Verbose      => 0
    ) or die "couldn't create nameserver object\n";

    $ns->main_loop;
}

###############################################################################
