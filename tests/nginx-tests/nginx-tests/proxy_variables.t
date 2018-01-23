#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module with upstream variables.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        server 127.0.0.1:8081;
        server 127.0.0.1:8081;
    }

    log_format time '$upstream_connect_time:$upstream_header_time:'
                    '$upstream_response_time';

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Connect $upstream_connect_time;
        add_header X-Header $upstream_header_time;
        add_header X-Response $upstream_response_time;

        location / {
            proxy_pass http://127.0.0.1:8081;
            access_log %%TESTDIR%%/time.log time;
        }

        location /pnu {
            proxy_pass http://u/bad;
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
$t->run_daemon(\&http_daemon, 8081);
$t->try_run('no upstream_connect_time')->plan(18);

$t->waitforsocket('127.0.0.1:8081');

###############################################################################

my $re = qr/(\d\.\d{3})/;
my ($ct, $ht, $rt, $ct2, $ht2, $rt2);

like(http_get('/vars'), qr/X-Proxy-Host:\s127\.0\.0\.1:8080/, 'proxy_host');
like(http_get('/vars'), qr/X-Proxy-Port:\s8080/, 'proxy_port');
like(http_xff('/vars', '192.0.2.1'), qr/X-Proxy-Forwarded:.*192\.0\.2\.1/,
	'proxy_add_x_forwarded_for');

($ct, $ht) = get('/header');
cmp_ok($ct, '<', 1, 'connect time - slow response header');
cmp_ok($ht, '>=', 1, 'header time - slow response header');

($ct, $ht) = get('/body');
cmp_ok($ct, '<', 1, 'connect time - slow response body');
cmp_ok($ht, '<', 1, 'header time - slow response body');

($ct, $ct2, $ht, $ht2, $rt) = get('/pnu', many => 1);
cmp_ok($ct, '<', 1, 'connect time - next');
cmp_ok($ct2, '<', 1, 'connect time - next 2');
cmp_ok($ht, '>=', 1, 'header time - next');
cmp_ok($ht2, '<', 1, 'header time - next 2');
is($ht, $rt, 'header time - bad response');

$t->stop();

($ct, $ht, $rt, $ct2, $ht2, $rt2)
	= $t->read_file('time.log') =~ /^$re:$re:$re\n$re:$re:$re$/;

cmp_ok($ct, '<', 1, 'connect time log - slow response header');
cmp_ok($ct2, '<', 1, 'connect time log - slow response body');

cmp_ok($ht, '>=', 1, 'header time log - slow response header');
cmp_ok($ht2, '<', 1, 'header time log - slow response body');

cmp_ok($rt, '>=', 1, 'response time log - slow response header');
cmp_ok($rt2, '>=', 1, 'response time log - slow response body');

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
	my ($port) = @_;
	my $once = 1;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $port,
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
		next unless defined $uri;

		if ($uri =~ 'bad' && $once) {
			$once = 0;
			sleep 1;
			next;
		}

		if ($uri =~ 'header') {
			sleep 1;
		}

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

SEE-THIS-
EOF

		if ($uri =~ 'body') {
			sleep 1;
		}

		print $client 'AND-THIS';
	}
}

###############################################################################
