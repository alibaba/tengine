#!/usr/bin/perl

# (C) cfsego

# Tests for request statistics features.

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

my $t = Test::Nginx->new()->has(qw/reqstat/);

my $cf_1 = <<'EOF';

%%TEST_GLOBALS%%

http {

    root %%TESTDIR%%;

    error_page default;

    req_status_zone server "$host,$server_addr:$server_port" 40M;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /usr {
                req_status_show;
        }

    }

    server {
        listen              3130;
        listen              3131;
        location / {
            rewrite_by_lua 'ngx.sleep(2);ngx.exit(500)';
        }
    }

    upstream test {
        server 127.0.0.1:3131 max_fails=0;
        server 127.0.0.1:3130 max_fails=0;
    }

    server {
        listen              127.0.0.1:3129;
        server_name         www.test_app_a.com;
        proxy_set_header    X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream error timeout http_500;
        req_status          server;

        location /proxy/ {
            proxy_pass http://test/;
        }

        location /302/ {
            return 302;
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

    root %%TESTDIR%%;

    req_status_zone server "$host,$server_addr:$server_port error" 40M;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /usr {
                req_status_show;
        }

    }

    server {
        listen              3130;
        req_status          server;
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

$t->plan(17);
$t->write_file_expand('nginx.conf', $cf_1);
$t->write_file('B4', '1234567890');
$t->run();
my $w=my_http_get('/B4', 'www.test_app_a.com', 3129);
warn length $w;
my $r = my_http_get('/usr', 'www.test_cp.com', 3128);

#1
like($r, qr/242/, 'length check');
#6
is (field($r, 6), 1, '2xx count is 1');
is (field($r, 7), 0, '3xx count is 0');
is (field($r, 8), 0, '4xx count is 0');
is (field($r, 9), 0, '5xx count is 0');

#2
$t->write_file_expand('nginx.conf', $cf_2);
#this time reload is failed
$t->reload();
sleep 2;
$t->write_file_expand('nginx.conf', $cf_1);
#succeed to reload
$t->reload();
sleep 2;
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/242/, 'reload length check');
my_http_get('/B4', 'www.test_app_a.com', 3129);

#3
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/484/, 'length check again');
#7
is (field($r, 6), 2, '2xx count is 2');
is (field($r, 7), 0, '3xx count is 0');
is (field($r, 8), 0, '4xx count is 0');
is (field($r, 9), 0, '5xx count is 0');

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

my_http_get('/proxy/B4', 'www.test_app_a.com', 3129);

#5
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/1,400\d,2\n/, 'upstream');

#14
my_http_get('/B3', 'www.test_app_a.com', 3129);
my_http_get('/B3', 'www.test_app_a.com', 3129);
my_http_get('/B3', 'www.test_app_a.com', 3129);
my_http_get('/302/B3', 'www.test_app_a.com', 3129);
my_http_get('/302/B3', 'www.test_app_a.com', 3129);
my_http_get('/302/B3', 'www.test_app_a.com', 3129);
my_http_get('/302/B3', 'www.test_app_a.com', 3129);
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
is (field($r, 6), 2, '2xx count is 2');
is (field($r, 7), 4, '3xx count is 4');
is (field($r, 8), 3, '4xx count is 3');
is (field($r, 9), 1, '5xx count is 1');




#################################################################################

sub my_http_ip {
    my ($request, $ip, $port) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(5);
        my $s = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => "${ip}:${port}"
        );  
        log_out($request);
        $s->print($request);
        local $/; 
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

sub my_http($;%) {
    my ($request, %extra) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(5);
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

sub my_http_get_ip {
    my ($url, $ip, $port) = @_;
    my $r = my_http_ip(<<EOF, $ip, $port);
GET $url HTTP/1.0
Connection: close

EOF
}

sub my_http_get {
    my ($url, $host, $port) = @_;
    my $r = my_http(<<EOF, 'port', $port);
GET $url HTTP/1.1
Host: $host
Connection: close

EOF
}

sub field {
    my ($result, $index) = @_;
    my @lines = split(m/\s/s, $result);
    my $content = $lines[-4];
    my @fields = split(/,/, $content);
    return $fields[$index];
}
