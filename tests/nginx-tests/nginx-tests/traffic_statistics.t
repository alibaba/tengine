#!/usr/bin/perl

# (C) cfsego

# Tests for traffic statistics features.

###############################################################################

use warnings;
use strict;

use Test::More;
use POSIX;
use Cwd qw/ realpath /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/ipstat/,qw/reqstat/);

$t->write_file_expand('B4', '1234');

my $cf_1 = <<'EOF';

%%TEST_GLOBALS%%

http {

    req_status_zone server "$host,$server_addr:$server_port" 40M;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /us {
                vip_status_show;
        }

        location /usr {
                req_status_show;
        }

    }

    server {
        listen              127.0.0.1:3129;
        server_name         www.test_app_a.com;
        req_status          server;

        location /test_proxy {
            proxy_pass http://sports.sina.com.cn;
        }
    }

    server {
        listen              127.0.0.1:3129;
        server_name         www.test_app_a1.com;
        req_status          server;
    }
}

events {
    use     epoll;
}

EOF

my $cf_2 = <<'EOF';

%%TEST_GLOBALS%%

http {

    req_status_zone server "$host,$server_addr:$server_port error" 40M;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /us {
                vip_status_show;
        }

        location /usr {
                req_status_show;
        }

    }

    server {
        listen              127.0.0.1:3129;
        server_name         www.test_app_a.com;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        req_status          server;
    }
}

events {
    use     epoll;
}

EOF

#################################################################################

$t->plan(12);
$t->write_file_expand('nginx.conf', $cf_1);
$t->run();
my_http_get('/B4', 'www.test_app_a.com', 3129);
my $r = my_http_get('/usr', 'www.test_cp.com', 3128);
#1
like($r, qr/753/, 'length check');
#2
$t->write_file_expand('nginx.conf', $cf_2);
#this time reload is failed
$t->reload();
$t->write_file_expand('nginx.conf', $cf_1);
#succeed to reload
$t->reload();
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/753/, 'reload length check');
my_http_get('/B4', 'www.test_app_a.com', 3129);
#3
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/1506/, 'length check again');
#4
my %c = ();
my $i;
my $s = 1;
foreach $i (split(/\r\n/, $r)) {
    if ($c{$i}) { fail('duplicate output'); $s = 0; last; }
    else { $c{$i} = 1; }
}
if ($s == 1) {
    pass('duplicate output');
}
#5 different time slice
my $j;
my $c1;
my $rt_min;
my $rt_min_1;
my $rt_max;
my $rt_max_1;
my $rt_avg;
my $rt_avg_1;
my_http_get('/test_proxy', 'www.test_app_a.com', 3129);
sleep 2;
my_http_get('/test_proxy', 'www.test_app_a.com', 3129);
$r = my_http_get('/us', 'www.test_cp.com', 3128);
foreach $i (split(/\r\n/, $r)) {
    if ($i =~ /127.0.0.1:3129/) {
        $c1 = 0;
        foreach $j (split(/,/, $i)) {
            if ($c1 == 8) {
                $rt_min = $j;
            } elsif ($c1 == 9) {
                $rt_max = $j;
            } elsif ($c1 == 10) {
                $rt_avg = $j;
            }
            $c1++;
        }
        last;
    }
}
$t->reload();
$r = my_http_get('/us', 'www.test_cp.com', 3128);
foreach $i (split(/\r\n/, $r)) {
    if ($i =~ /127.0.0.1:3129/) {
        $c1 = 0;
        foreach $j (split(/,/, $i)) {
            if ($c1 == 8) {
                $rt_min_1 = $j;
            } elsif ($c1 == 9) {
                $rt_max_1 = $j;
            } elsif ($c1 == 10) {
                $rt_avg_1 = $j;
            }
            $c1++;
        }
        last;
    }
}
is($rt_min, $rt_min_1, "min value should be preserved during reload");
is($rt_max, $rt_max_1, "max value should be preserved during reload");
is($rt_avg, $rt_avg_1, "avg value should be preserved during reload");
cmp_ok($rt_min, "<=", $rt_max, "min value should be no bigger than max value");
#6 the same time slice
$t->stop();
sleep 1;
$t->run();
my_http_get('/test_proxy', 'www.test_app_a.com', 3129);
my_http_get('/test_proxy', 'www.test_app_a.com', 3129);
$r = my_http_get('/us', 'www.test_cp.com', 3128);
foreach $i (split(/\r\n/, $r)) {
    if ($i =~ /127.0.0.1:3129/) {
        $c1 = 0;
        foreach $j (split(/,/, $i)) {
            if ($c1 == 8) {
                $rt_min = $j;
            } elsif ($c1 == 9) {
                $rt_max = $j;
            } elsif ($c1 == 10) {
                $rt_avg = $j;
            }
            $c1++;
        }
        last;
    }
}
$t->reload();
$r = my_http_get('/us', 'www.test_cp.com', 3128);
foreach $i (split(/\r\n/, $r)) {
    if ($i =~ /127.0.0.1:3129/) {
        $c1 = 0;
        foreach $j (split(/,/, $i)) {
            if ($c1 == 8) {
                $rt_min_1 = $j;
            } elsif ($c1 == 9) {
                $rt_max_1 = $j;
            } elsif ($c1 == 10) {
                $rt_avg_1 = $j;
            }
            $c1++;
        }
        last;
    }
}
is($rt_min, $rt_min_1, "min value should be preserved during reload");
is($rt_max, $rt_max_1, "max value should be preserved during reload");
is($rt_avg, $rt_avg_1, "avg value should be preserved during reload");
cmp_ok($rt_min, "<=", $rt_max, "min value should be no bigger than max value");
$t->stop();
#################################################################################

sub my_http($;%) {
    my ($request, %extra) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(2);
        my $s = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => "127.0.0.1:$extra{port}"
        );  
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


sub my_http_get {
    my ($url, $host, $port) = @_;
    my $r = my_http(<<EOF, 'port', $port);
GET $url HTTP/1.1
Host: $host
Connection: close

EOF
}
