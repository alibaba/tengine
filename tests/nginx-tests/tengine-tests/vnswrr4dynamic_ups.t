#!/usr/bin/perl

#Copyright (C) 2010-2019 Alibaba Group Holding Limited

# Tests for vnswrr and dynamic resolve in upstream module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
eval { require Net::DNS::Nameserver; };
plan(skip_all => 'Net::DNS::Nameserver not installed') if $@;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(6);
my @domain_addrs = ("127.0.0.2");

my $ipv6 = $t->has_version('1.11.5') ? "ipv6=off" : "";

my $nginx_conf = <<'EOF';

%%TEST_GLOBALS%%

daemon         off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    resolver 127.0.0.1:53530 valid=1s %%TEST_CONF_IPV6%%;
    resolver_timeout 1s;

    upstream backend {
        vnswrr;
        server www.taobao.com fail_timeout=0s;

        server 127.0.0.1:8081 backup;
    }

    upstream backend1 {
        vnswrr;
        dynamic_resolve;

        server www.taobao.com:8081 fail_timeout=0s;
        server 127.0.0.1:8081 backup;
    }

    upstream backend2 {
        vnswrr;
        dynamic_resolve fallback=stale;

        server www.taobao.com:8081 fail_timeout=0s;
    }

    upstream backend3 {
        vnswrr;
        dynamic_resolve fallback=next;

        server www.taobao.com:8081 fail_timeout=0s;
        server 127.0.0.1:8081 backup;
    }

    upstream backend4 {
        vnswrr;
        dynamic_resolve fallback=shutdown;

        server www.taobao.com:8081 fail_timeout=0s;
        server 127.0.0.1:8081 backup;
    }

    upstream backend-ka {
        vnswrr;
        server www.taobao.com;

        keepalive 8;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /static {
            add_header UPS $upstream_addr always;
            proxy_pass http://backend;
        }

        location / {
            proxy_pass http://backend1;
        }

        location /proxy_pass_var {
            set $up backend1;
            proxy_pass http://$up;
        }

        location /stale {
            proxy_pass http://backend2;
        }

        location /next {
            proxy_pass http://backend3;
        }

        location /shutdown {
            proxy_pass http://backend4;
        }
    }

    server {
        # must listen on 127.0.0.2, dont replace port
        listen 127.0.0.02:8081;
        return 200 "from server 127.0.0.2";
    }

    server {
        listen 127.0.0.1:8081;

        location / {
            return 404 "Oops, '$uri' not found";
        }

        location /proxy_pass_var {
            return 200 "cannot be here! It should go to 127.0.0.02:8081";
        }

        location /stale {
            return 200 "from server 127.0.0.2";
        }

        location /next {
            return 200 "from server 127.0.0.4";
        }

        location /static {
            return 200 "from server 127.0.0.4";
        }
    }
}

EOF

$nginx_conf =~ s/%%TEST_CONF_IPV6%%/$ipv6/gmse;

$t->write_file_expand('nginx.conf', $nginx_conf);

$t->run_daemon(\&dns_server_daemon);
my $dns_pid = pop @{$t->{_daemons}};

$t->run();

###############################################################################

unlike(http_get('/static'), qr/127.0.0.4/,
    'static resolved should be taobao\' IP addr');
like(http_get('/'), qr/127\.0\.0\.2/,
    'http server should be 127.0.0.2');

# test variable in proxy_pass argument
like(http_get('/proxy_pass_var'), qr/127\.0\.0\.2/,
    'http server should be 127.0.0.2 for /proxy_pass_var');

# kill dns daemon
kill $^O eq 'MSWin32' ? 9 : 'TERM', $dns_pid;
wait;

# wait for dns cache to expire
sleep(2);

unlike(http_get('/stale'), qr/127\.0\.0\.2/,
    'stale http server should be www.taobao.com:8081, using initial result');

like(http_get('/shutdown'), qr/502 Bad Gateway/,
    'shutdown connection if dns query is failed');

like(http_get('/next'), qr/127\.0\.0\.4/, 'next upstream should be 127.0.0.4');

###############################################################################

sub reply_handler {
    my ($qname, $qclass, $qtype, $peerhost,$query,$conn) = @_;
    my ($rcode, $rr, $ttl, $rdata, @ans, @auth, @add,);

    $query->print;

    if ($qtype ne "A") {
        $rcode = "NXDOMAIN";
        return ($rcode, \@ans, \@auth, \@add, { aa => 1 });
    }

    if ($qname eq "www.taobao.com") {
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
        LocalAddr    => '127.0.0.1',
        LocalPort    => 53530,
        ReplyHandler => \&reply_handler,
        Verbose      => 0
    ) or die "couldn't create nameserver object\n";

    $ns->main_loop;
}

###############################################################################
