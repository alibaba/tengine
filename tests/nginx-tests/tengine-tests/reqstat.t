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

my $t = Test::Nginx->new()->has('reqstat');

my $cf_1 = <<'EOF';

%%TEST_GLOBALS%%

http {

    root %%TESTDIR%%;

    error_page default;

    req_status_zone server "$host,$server_addr:$server_port" 40M;
    req_status_zone test   "$uri"   40M;
    req_status_zone test1  "$uri"   40M;
    req_status_zone_add_indicator test $test1 $upstream_response_time;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /usr {
                req_status_show server;
        }

        location /usr1 {
                req_status_show test;
        }

        location /usr2 {
                req_status_show test1;
        }
    }

    server {
        listen              3130;
        listen              3131;
        location / {
            rewrite_by_lua 'ngx.sleep(2);ngx.exit(500)';
        }

        location = /404 {
            return 404;
        }

        location = /504 {
            return 504;
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
        req_status_bypass   $bypass;

        set $bypass 0;
        if ($uri = '/BYPASS') {
            set $bypass 1;
        }

        location /proxy/ {
            req_status      server test test1;
            set $test1      2;
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

$t->plan(52);
$t->write_file_expand('nginx.conf', $cf_1);
$t->write_file('B4', '1234567890');
$t->write_file('BYPASS', '1234567890');
$t->run();
my $w = my_http_get('/B4', 'www.test_app_a.com', 3129);
warn length $w;
my $r = my_http_get('/usr', 'www.test_cp.com', 3128);

#1
like($r, qr/242/, 'length check');
#6
is (field($r, 6), 1, '2xx count is 1');
is (field($r, 7), 0, '3xx count is 0');
is (field($r, 8), 0, '4xx count is 0');
is (field($r, 9), 0, '5xx count is 0');

is (field($r, 15), 1, '200 count is 1');
is (field($r, 17), 0, '302 count is 0');
is (field($r, 20), 0, '404 count is 0');
is (field($r, 23), 0, '500 count is 0');

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
$r = my_http_get('/B4', 'www.test_app_a.com', 3129);

#3
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
like($r, qr/484/, 'length check again');
#7
is (field($r, 6), 2, '2xx count is 2');
is (field($r, 7), 0, '3xx count is 0');
is (field($r, 8), 0, '4xx count is 0');
is (field($r, 9), 0, '5xx count is 0');

is (field($r, 15), 2, '200 count is 2');
is (field($r, 17), 0, '302 count is 0');
is (field($r, 20), 0, '404 count is 0');
is (field($r, 23), 0, '500 count is 0');

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
like($r, qr/1,400\d,2/, 'upstream');
my $r1 = content(my_http_get('/usr1', 'www.test_cp.com', 3128));
my $r2 = content(my_http_get('/usr2', 'www.test_cp.com', 3128));
$r = substr($r1, length($r2), length($r1)-length($r2));
like($r, qr/^,2,200\d$/, 'user defined variable');

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

is (field($r, 15), 2, '200 count is 2');
is (field($r, 17), 4, '302 count is 4');
is (field($r, 20), 3, '404 count is 3');
is (field($r, 23), 1, '500 count is 1');

#18
my_http_get('/BYPASS', 'www.test_app_a.com', 3129);
my_http_get('/BYPASS', 'www.test_app_a.com', 3129);
my_http_get('/BYPASS', 'www.test_app_a.com', 3129);

$r = my_http_get('/usr', 'www.test_cp.com', 3128);

is (field($r, 6), 2, '2xx count is 2');
is (field($r, 15), 2, '200 count is 2');

$t->stop();

#--- test ups 4xx/5xx ---
sleep(2);
$t->run();
sleep(2);
like(my_http_get('/proxy/404', 'www.test_app_a.com', 3129), qr/HTTP\/1\.. 404/, "request /proxy/404");
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
is (field($r, 20), 1, '404 count is 1');
is (field($r, 26), 0, '504 count is 0');
is (field($r, 29), 1, 'ups 4xx count is 1');
is (field($r, 30), 0, 'ups 5xx count is 0');

like(my_http_get('/proxy/504', 'www.test_app_a.com', 3129), qr/HTTP\/1\.. 504/, "request /proxy/404");
$r = my_http_get('/usr', 'www.test_cp.com', 3128);
is (field($r, 20), 1, '404 count is 1');
is (field($r, 26), 1, '504 count is 1');
is (field($r, 29), 1, 'ups 4xx count is 1');
is (field($r, 30), 1, 'ups 5xx count is 1');

$t->stop();

my $cf_3 = <<'EOF';

%%TEST_GLOBALS%%

http {

    root %%TESTDIR%%;

    error_page default;

    req_status_zone         test3   "$uri"   1M;
    req_status_zone_recycle test3   1  1;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location / {
            req_status      test3;
        }

        location /usr {
            req_status_show test3;
        }
    }
}

events {
    use     epoll;
}

EOF

#---test recycle----
$t->write_file_expand('nginx.conf', $cf_3);
$t->stop;
sleep(2);
$t->run();

for $i (0..1009) {
  my_http_get('/test' . $i, 'www.test_cp.com', 3128);
}

$r = my_http_get('/usr', 'www.test_cp.com', 3128);
unlike($r, qr/test1008/, 'test1008 is dropped because any is not spare');
unlike($r, qr/test1009/, 'test1009 is dropped because any is not spare');

sleep 1;

my_http_get('/test1007', 'www.test_cp.com', 3128);
my_http_get('/test1008', 'www.test_cp.com', 3128);

$r = my_http_get('/usr', 'www.test_cp.com', 3128);

unlike($r, qr/test0/, 'test0 is recycled');
like($r, qr/test1008/, 'test0 is recycled for test1008');

(my $l) = $r =~ /(.*test1007.*)/;
is (field_line($l, 4), 2, 'request count is 2 after recycle');
($l) = $r =~ /(.*test1008.*)/;
is (field_line($l, 4), 1, 'request count is 1');

$t->stop();

my $cf_4 = <<'EOF';

%%TEST_GLOBALS%%

http {

    root %%TESTDIR%%;

    error_page default;

    req_status_zone                    test3   "$uri"   1M;
    req_status_zone_recycle            test3   1  1;
    req_status_zone_key_length  test3  4;
    req_status                         test3;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /usr {
                req_status_show test3;
        }
    }
}

events {
    use     epoll;
}

EOF

#---test key length----
$t->write_file_expand('nginx.conf', $cf_4);
$t->stop;
sleep(2);
$t->run();

for $i (0..1) {
  my_http_get('/test' . $i, 'www.test_cp.com', 3128);
}

sleep 1;

$r = my_http_get('/usr', 'www.test_cp.com', 3128);

#warn $r;

my @lines = split(m/\s/s, $r);
my @content = @lines[-5,-4];
is ($content[0], $content[1], 'key cut');

my $cf_5 = <<'EOF';

%%TEST_GLOBALS%%

worker_rlimit_core   10000M;

http {

    root %%TESTDIR%%;

    req_status_zone server "$host,$server_addr:$server_port" 40M;
    req_status_zone server1 "$server_port" 10M;

    req_status_zone_add_indicator  server1 $root;

    server {
        listen              3128;
        server_name         www.test_cp.com;

        location /usr {
                req_status_show server;
        }

        location /usr_1 {
                req_status_show          server1;
                req_status_show_field    req_total $root;
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
        proxy_intercept_errors on;

        error_page 500 /B4;

        set $root 0;
        req_status      server1;

        if ($uri = '/') {
            set $root 1;
        }

        location /proxy/ {
            req_status          server server1;
            proxy_pass http://test/;
        }

        location /302/ {
            return 302;
        }
    }

    server {
        listen              127.0.0.1:3129;
        server_name         www.test_app_a1.com;
    }

    server {
        listen              127.0.0.1:3127;
        server_name         www.test_app_a2.com;
        req_status          server;
        rewrite  .   http://www.taobao.com;
    }
}

events {
    use     epoll;
}

EOF


#---test error page----
$t->write_file_expand('nginx.conf', $cf_5);
#this time for error_page redirect
$t->stop();
sleep(2);
$t->run();

my_http_get('/proxy/B4', 'www.test_app_a.com', 3129);
my_http_get('/proxy/B4', 'www.test_app_a.com', 3129);

$r = my_http_get('/usr', 'www.test_cp.com', 3128);
is (field($r, 9), 2, '5xx count is 2');

$t->stop();
sleep(2);
$t->run();

my_http_get('/proxy/B4', 'www.test_app_a2.com', 3127);
my_http_get('/proxy/B4', 'www.test_app_a2.com', 3127);
my_http_get('/', 'www.test_app_a.com', 3129);
my_http_get('/', 'www.test_app_a.com', 3129);
my_http_get('/proxy/B4', 'www.test_app_a.com', 3129);
my_http_get('/proxy/B4', 'www.test_app_a.com', 3129);

$r = my_http_get('/usr', 'www.test_cp.com', 3128);
is (field($r, 7), 2, '3xx count is 2 when rewrite in server');
$r = my_http_get('/usr_1', 'www.test_cp.com', 3128);
like($r, qr/3129,4,2/, 'req_status_show_field and req_status_zone_add_indicator');

$t->stop();

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

sub field_line {
    my ($line, $index) = @_;
    my @fields = split(/,/, $line);
    return $fields[$index];
}

sub field {
    my ($result, $index) = @_;
    my $content = content($result);
    my @fields = split(/,/, $content);
    return $fields[$index];
}

sub content {
    my ($result) = @_;
    my @lines = split(m/\s/s, $result);
    my $content = $lines[-4];
    return $content;
}
