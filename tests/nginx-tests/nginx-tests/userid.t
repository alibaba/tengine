#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for userid filter module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Config;
use MIME::Base64;
use Time::Local;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http userid map/)->plan(33);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $args $uid_reset {
        default      0;
        value        1;
        log          log;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Got $uid_got;
        add_header X-Reset $uid_reset;
        add_header X-Set $uid_set;
        userid on;

        location / {
            error_log %%TESTDIR%%/error.log debug;
            error_log %%TESTDIR%%/error_reset.log info;
        }

        location /name {
            userid_name test;
        }

        location /path {
            userid_path /0123456789;

            location /path/r {
                userid_path /9876543210;
            }
        }

        location /domain {
            userid_domain test.domain;
        }

        location /mark_off {
            userid_mark off;
        }
        location /mark_eq {
            userid_mark =;
        }
        location /mark_let {
            userid_mark t;
        }
        location /mark_num {
            userid_mark 9;
        }

        location /expires_time {
            add_header X-Msec $msec;
            userid_expires 100;
        }
        location /expires_max {
            userid_expires max;

            location /expires_max/off {
                userid_expires off;
            }
        }
        location /expires_off {
            userid_expires off;
        }

        location /p3p {
            userid_p3p policyref="/w3c/p3p.xml";
        }

        location /service {
            userid_service 65534;
        }

        location /cv1 {
            userid v1;
            userid_mark t;
        }

        location /clog {
            userid log;
        }

        location /coff {
            userid off;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('expires_time', '');
$t->write_file('service', '');
$t->write_file('cv1', '');
$t->write_file('clog', '');
$t->write_file('coff', '');
$t->run();

###############################################################################

# userid

like(http_get('/'), qr/Set-Cookie:/, 'cookie on');
like(http_get('/cv1'), qr/Set-Cookie:/, 'cookie v1');
unlike(http_get('/clog'), qr/Set-Cookie:/, 'cookie log');
unlike(http_get('/coff'), qr/Set-Cookie:/, 'cookie off');

# default

my %cookie = get_cookie('/');
isnt($cookie{'uid'}, undef, 'name default');
is($cookie{'path'}, '/', 'path default');
is($cookie{'domain'}, undef, 'domain default');
is($cookie{'expires'}, undef, 'expires default');
like($cookie{'uid'}, '/\w+={0,2}$/', 'mark default');
unlike(http_get('/'), qr/^P3P/m, 'p3p default');
like(http_get('/'), qr/X-Reset: 0/, 'uid reset variable default');

# name, path, domain and p3p

isnt(get_cookie('/name', 'test'), undef, 'name');
is(get_cookie('/path', 'path'), '/0123456789', 'path');
is(get_cookie('/domain', 'domain'), 'test.domain', 'domain');
like(http_get('/p3p'), qr!P3P: policyref="/w3c/p3p.xml"!, 'p3p');

# mark

like(get_cookie('/mark_off', 'uid'), '/\w+={0,2}$/', 'mark off');
like(get_cookie('/mark_eq', 'uid'), '/==$/', 'mark equal');
like(get_cookie('/mark_let', 'uid'), '/t=$/', 'mark letter');
like(get_cookie('/mark_num', 'uid'), '/9=$/', 'mark number');

# expires

my $r = http_get('/expires_time');
my ($t1) = $r =~ /X-Msec: (\d+)/;
is(expires2timegm(cookie($r, 'expires')), $t1 + 100, 'expires time');
is(get_cookie('/expires_max', 'expires'), 'Thu, 31-Dec-37 23:55:55 GMT',
	'expires max');
is(get_cookie('/expires_off', 'expires'), undef, 'expires off');

# redefinition

unlike(http_get('/expires_max/off'), qr/expires/, 'redefine expires');
like(http_get('/path/r'), qr!/9876543210!, 'redefine path');

# requests

$r = http_get('/');
my ($uid) = uid_set($r);
isnt($uid, undef, 'uid set variable');

$r = send_uid('/', cookie($r, 'uid'));
is(uid_got($r), $uid, 'uid got variable');
unlike($r, qr/Set-Cookie:/, 'same path request');

$r = send_uid('/coff', $uid);
unlike($r, qr/Set-Cookie:/, 'other path request');

$r = send_uid('/?value', $uid);
like($r, qr/Set-Cookie:/, 'uid reset variable value');

# service

is(substr(uid_set(http_get('/cv1')), 0, 8), '00000000', 'service default v1');

my $bigendian = $Config{byteorder} =~ '1234' ? 0 : 1;
my $addr = $bigendian ? "7F000001" : "0100007F";
is(substr(uid_set(http_get('/')), 0, 8), $addr, 'service default v2');

$addr = $bigendian ? "0000FFFE" : "FEFF0000";
is(substr(uid_set(http_get('/service')), 0, 8), $addr, 'service custom');

# reset log

send_uid('/?log', cookie($r, 'uid'));

$t->stop();

like($t->read_file('error_reset.log'),
	'/userid cookie "uid=\w+" was reset/m', 'uid reset variable log');

###############################################################################

sub cookie {
	my ($r, $key) = @_;
	my %cookie;

	$r =~ /(Set-Cookie:[^\x0d]*).*\x0d\x0a?\x0d/ms;
	if ($1) {
		%cookie = $1 =~ /(\w+)=([^;]+)/g;
	}

	return $cookie{$key} if defined $key;
	return %cookie;
}

sub get_cookie {
	my ($url, $key) = @_;
	return cookie(http_get($url), $key);
}

sub expires2timegm {
	my ($e) = @_;
	my %months = (Jan => 0, Feb => 1, Mar => 2, Apr => 3, May =>4, Jun => 5,
		Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);

	my ($w, $date, $time) = split(" ", $e);
	my ($day, $month, $year) = split("-", $date);
	my ($hour, $min, $sec) = split(":", $time);

	return timegm($sec, $min, $hour, $day, $months{$month}, $year);
}

sub uid_set {
	my ($r) = @_;
	my ($uid) = $r =~ /X-Set: uid=(.*)\n/m;
	return $uid;
}

sub uid_got {
	my ($r) = @_;
	my ($uid) = $r =~ /X-Got: uid=(.*)\n/m;
	return $uid;
}

sub send_uid {
	my ($url, $uid) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Cookie: uid=$uid

EOF
}

###############################################################################
