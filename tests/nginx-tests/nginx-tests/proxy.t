#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)->plan(30);

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

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_read_timeout 1s;
            proxy_connect_timeout 2s;
        }

        location /var {
            proxy_pass http://$arg_b;
            proxy_read_timeout 1s;
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
            proxy_pass http://127.0.0.1:8080/stub;

            add_header X-Proxy-Host $proxy_host;
            add_header X-Proxy-Port $proxy_port;
            add_header X-Proxy-Forwarded $proxy_add_x_forwarded_for;
        }

        location /stub { }
    }
}

EOF

$t->write_file('stub', '');
$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'proxy request');
like(http_get('/multi'), qr/AND-THIS/, 'proxy request with multiple packets');

unlike(http_head('/'), qr/SEE-THIS/, 'proxy head request');

like(http_get('/var?b=127.0.0.1:' . port(8081) . '/'), qr/SEE-THIS/,
	'proxy with variables');
like(http_get('/var?b=u/'), qr/SEE-THIS/, 'proxy with variables to upstream');

like(http_get('/timeout'), qr/200 OK/, 'proxy connect timeout');

my $re = qr/(\d\.\d{3})/;
my $p0 = port(8080);
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

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.7');

is($ht, '-', 'header time - next');

}

cmp_ok($ht2, '<', 1, 'header time - next 2');
cmp_ok($rt, '>=', 1, 'response time - next');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.7');

is($rt2, '-', 'response time - next 2');

}

$t->stop();

($ct, $ht, $rt, $ct2, $ht2, $rt2, $ct3, $ht3, $rt3)
	= $t->read_file('time.log') =~ /^$re:$re:$re\n$re:$re:$re\n$re:$re:$re$/;

cmp_ok($ct, '<', 1, 'connect time log - slow response header');
cmp_ok($ct2, '<', 1, 'connect time log - slow response body');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.7');

isnt($ct3, '-', 'connect time log - client close set');

}

$ct3 = 0 if $ct3 eq '-';
cmp_ok($ct3, '<', 1, 'connect time log - client close');

cmp_ok($ht, '>=', 1, 'header time log - slow response header');
cmp_ok($ht2, '<', 1, 'header time log - slow response body');
is($ht3, '-', 'header time log - client close');

cmp_ok($rt, '>=', 1, 'response time log - slow response header');
cmp_ok($rt2, '>=', 1, 'response time log - slow response body');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.15.7');

isnt($rt3, '-', 'response time log - client close set');
$rt3 = 0 if $rt3 eq '-';
cmp_ok($rt3, '>', $ct3, 'response time log - client close');

}

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
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		my $headers = '';
		my $uri = '';

		while (<$client>) {
			$headers .= $_;
			last if (/^\x0d?\x0a?$/);
		}

		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/') {
			print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
			print $client "TEST-OK-IF-YOU-SEE-THIS"
				unless $headers =~ /^HEAD/i;

		} elsif ($uri eq '/multi') {

			print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close

TEST-OK-IF-YOU-SEE-THIS
EOF

			select undef, undef, undef, 0.1;
			print $client 'AND-THIS';

		} elsif ($uri eq '/timeout') {
			sleep 3;

			print $client <<"EOF";
HTTP/1.1 200 OK
Connection: close

EOF

		} elsif ($uri eq '/bad') {

			if ($once) {
				$once = 0;
				select undef, undef, undef, 1.1;
				next;
			}

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

SEE-THIS-AND-THIS
EOF

		} elsif ($uri eq '/header') {
			select undef, undef, undef, 1.1;

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

SEE-THIS-AND-THIS;
EOF

		} elsif ($uri eq '/body') {

			print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

SEE-THIS-
EOF

			select undef, undef, undef, 1.1;
			print $client 'AND-THIS';

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

###############################################################################
