#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy module to HTTP/2 backend.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format time '$upstream_connect_time:$upstream_header_time:'
                    '$upstream_response_time';

    upstream u {
        server 127.0.0.1:8081;
    }

    upstream u2 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Connect $upstream_connect_time;
        add_header X-Header $upstream_header_time;
        add_header X-Response $upstream_response_time;

        proxy_http_version 2;
        sendfile off;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 2s;
            proxy_connect_timeout 2s;
        }

        location /var {
            proxy_pass http://$arg_b;
            proxy_read_timeout 2s;
            proxy_connect_timeout 2s;
        }

        location /timeout {
            proxy_pass http://127.0.0.1:8081;
            proxy_connect_timeout 2s;
        }

        location /time/ {
            proxy_pass http://127.0.0.1:8081/;
            access_log %%TESTDIR%%/time.log time;
        }

        location /pnu {
            proxy_pass http://u2/bad;
        }

        location /vars {
            proxy_pass http://127.0.0.1:8081/;

            add_header X-Proxy-Host $proxy_host;
            add_header X-Proxy-Port $proxy_port;
            add_header X-Proxy-Forwarded $proxy_add_x_forwarded_for;
        }
    }
}

EOF

$t->write_file('stub', '');
$t->run_daemon(\&http_daemon);
$t->waitforsocket('127.0.0.1:' . port(8081));

$t->try_run('no proxy_http_version 2')->plan(28);

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'proxy request');
like(http_get('/multi'), qr/AND-THIS/, 'proxy request with multiple packets');

unlike(http_head('/'), qr/SEE-THIS/, 'proxy head request');

like(http_get('/var?b=127.0.0.1:' . port(8081) . '/'), qr/SEE-THIS/,
	'proxy with variables');
like(http_get('/var?b=u/'), qr/SEE-THIS/, 'proxy with variables to upstream');

like(http_get('/timeout'), qr/200 OK/, 'proxy connect timeout');

my $re = qr/(\d\.\d{3})/;
my $p0 = port(8081);
my ($ct, $ht, $rt, $ct2, $ht2, $rt2, $ct3, $ht3, $rt3);

like(http_get('/vars'), qr/X-Proxy-Host:\s127\.0\.0\.1:$p0/, 'proxy_host');
like(http_get('/vars'), qr/X-Proxy-Port:\s$p0/, 'proxy_port');
like(http_xff('/vars', '192.0.2.1'), qr/X-Proxy-Forwarded:.*192\.0\.2\.1/,
	'proxy_add_x_forwarded_for');

($ct, $ht) = get('/time/header');
cmp_ok($ct, '<', 1, 'connect time - slow response header');
cmp_ok($ht, '>=', 1, 'header time - slow response header');

($ct, $ht) = get('/time/body');
cmp_ok($ct, '<', 1, 'connect time - slow response body');
cmp_ok($ht, '<', 1, 'header time - slow response body');

my $s = http_get('/time/header', start => 1);
select undef, undef, undef, 0.4;
close ($s);

# expect no header time in 1st (bad) upstream, no (yet) response time in 2nd

$re = qr/(\d\.\d{3}|-)/;
($ct, $ct2, $ht, $ht2, $rt, $rt2) = get('/pnu', many => 1);

cmp_ok($ct, '<', 1, 'connect time - next');
cmp_ok($ct2, '<', 1, 'connect time - next 2');

is($ht, '-', 'header time - next');
cmp_ok($ht2, '<', 1, 'header time - next 2');

cmp_ok($rt, '>=', 1, 'response time - next');
is($rt2, '-', 'response time - next 2');

$t->stop();

($ct, $ht, $rt, $ct2, $ht2, $rt2, $ct3, $ht3, $rt3)
	= $t->read_file('time.log') =~ /^$re:$re:$re\n$re:$re:$re\n$re:$re:$re$/;

cmp_ok($ct, '<', 1, 'connect time log - slow response header');
cmp_ok($ct2, '<', 1, 'connect time log - slow response body');
cmp_ok($ct3, '<', 1, 'connect time log - client close');

cmp_ok($ht, '>=', 1, 'header time log - slow response header');
cmp_ok($ht2, '<', 1, 'header time log - slow response body');
is($ht3, '-', 'header time log - client close');

cmp_ok($rt, '>=', 1, 'response time log - slow response header');
cmp_ok($rt2, '>=', 1, 'response time log - slow response body');
cmp_ok($rt3, '>', $ct3, 'response time log - client close');

###############################################################################

sub get {
	my ($uri, %extra) = @_;
	my $re = $extra{many} ? qr/$re, $re?/ : $re;
	my $r = http_get($uri);
	$r =~ /X-Connect: $re/, $r =~ /X-Header: $re/, $r =~ /X-Response: $re/;
}

sub http_xff {
	my ($uri, $xff) = @_;
	return http(<<EOF);
GET $uri HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

sub http_daemon {
	my $once = 1;
	my $client;
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while ($client = $server->accept()) {
		$client->autoflush(1);
		$client->sysread(my $buf, 24) == 24 or next; # preface

		my $c = Test::Nginx::HTTP2->new(1, socket => $client,
			pure => 1, preface => "") or next;

		$c->h2_settings(0);
		$c->h2_settings(1);

		my $frames = $c->read(all => [{ fin => 4 }]);
		my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
		my $sid = $frame->{sid};
		my $uri = $frame->{headers}{':path'};

		if ($uri eq '/') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS');

		} elsif ($uri eq '/multi') {
			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS', { body_more => 1 });

			select undef, undef, undef, 0.1;
			$c->h2_body('AND-THIS');

		} elsif ($uri eq '/timeout') {
			sleep 3;

			$c->new_stream({ headers => [
				{ name => ':status', value => '200' },
			]}, $sid);

		} elsif ($uri eq '/bad') {

			if ($once) {
				$once = 0;
				select undef, undef, undef, 1.1;
				close $client;
				next;
			}

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS');

		} elsif ($uri eq '/header') {
			select undef, undef, undef, 1.1;

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS');

		} elsif ($uri eq '/body') {

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '200' },
			]}, $sid);
			$c->h2_body('SEE-THIS-', { body_more => 1 });

			select undef, undef, undef, 1.1;
			$c->h2_body('AND-THIS');

		} else {

			$c->new_stream({ body_more => 1, headers => [
				{ name => ':status', value => '404' },
			]}, $sid);
			$c->h2_body("Oops, '$uri' not found");
		}
	}
}

###############################################################################
