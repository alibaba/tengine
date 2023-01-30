#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for http keepalive directives.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test1 $sent_http_connection;
    log_format test2 $sent_http_keep_alive;
    access_log %%TESTDIR%%/test1.log test1 if=$arg_l;
    access_log %%TESTDIR%%/test2.log test2 if=$arg_l;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        keepalive_requests  2;
        keepalive_timeout   1 9;

        add_header X-Conn $connection_requests:$connection_time;

        location / { }
        location /r {
            keepalive_requests  4;
            keepalive_timeout   30s;
        }

        location /time {
            keepalive_requests  100;
            keepalive_timeout   75s;
            keepalive_time      1s;
        }

        location /safari {
            keepalive_disable  safari;
        }

        location /none {
            keepalive_disable  none;
        }

        location /zero {
            keepalive_timeout  0;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->write_file('r', '');
$t->write_file('time', '');
$t->write_file('safari', '');
$t->write_file('none', '');
$t->write_file('zero', '');
$t->run()->plan(21);

###############################################################################

# keepalive_requests

like(http_keepalive('/'), qr/Connection: keep-alive/, 'keepalive request');
is(count_keepalive(http_keepalive('/?l=ok', req => 2)), 1, 'keepalive limit');
is(count_keepalive(http_keepalive('/r', req => 3)), 3, 'keepalive merge');
is(count_keepalive(http_keepalive('/r', req => 5)), 3, 'keepalive merge limit');

# keepalive_disable

like(http_keepalive('/', method => 'POST', ua => "MSIE 5.0"),
	qr/Connection: close/, 'keepalive disable msie6');
like(http_keepalive('/', ua => "MSIE 5.0"), qr/Connection: keep-alive/,
	'keepalive disable msie6 GET');
like(http_keepalive('/', method => 'POST', ua => "MSIE 7.0"),
	qr/Connection: keep-alive/, 'keepalive disable msie6 modern');
like(http_keepalive('/', ua => "Mac OS X Safari/7534.48.3"),
	qr/Connection: keep-alive/, 'keepalive disable msie6 safari');
like(http_keepalive('/safari', ua => "Mac OS X Safari/7534.48.3"),
	qr/Connection: close/, 'keepalive disable safari');
like(http_keepalive('/none', method => 'POST', ua => "MSIE 5.0"),
	qr/Connection: keep-alive/, 'keepalive disable none');

# keepalive_timeout

my $r = http_keepalive('/', req => 2, sleep => 2.1);
is(count_keepalive($r), 1, 'keepalive timeout request');
like($r, qr/Keep-Alive: timeout=9/, 'keepalive timeout header');

like(http_keepalive('/zero'), qr/Connection: close/, 'keepalive timeout 0');

# keepalive_time

$r = http_keepalive('/time', req => 3);
is(() = $r =~ /(200 OK)/g, 3, 'keepalive time requests');
unlike($r, qr/Connection: close/, 'keepalive time connection');

$r = http_keepalive('/time', req => 3, sleep => 1.2);
is(() = $r =~ /(200 OK)/g, 2, 'keepalive time limit requests');
like($r, qr/Connection: close/, 'keepalive time limit connection');

like($r, qr/X-Conn: 1:0.*X-Conn: 2:[^0]/s, 'keepalive time limit variables');

# cancel keepalive on EOF while discarding body

my $s = http(<<EOF, start => 1);
POST /r HTTP/1.1
Host: localhost
Content-Length: 10

EOF

read_keepalive($s);
shutdown($s, 1);

ok(IO::Select->new($s)->can_read(3), 'EOF in discard body');

$t->stop();

TODO: {
local $TODO = 'not yet';

is($t->read_file('test1.log'), "keep-alive\nclose\n", 'sent_http_connection');
is($t->read_file('test2.log'), "timeout=9\n-\n", 'sent_http_keep_alive');

}

###############################################################################

sub http_keepalive {
	my ($url, %opts) = @_;
	my $total = '';

	$opts{ua} = $opts{ua} || '';
	$opts{req} = $opts{req} || 1;
	$opts{sleep} = $opts{sleep} || 0;
	$opts{method} = $opts{method} || 'GET';

	local $SIG{PIPE} = 'IGNORE';

	my $s = http('', start => 1);

	for my $i (1 .. $opts{req}) {

		my $sleep = ($i == 1 ? $opts{sleep} : 0);

		http(<<EOF, socket => $s, start => 1, sleep => $sleep);
$opts{method} $url HTTP/1.1
Host: localhost
User-Agent: $opts{ua}

EOF

		$total .= read_keepalive($s);
	}

	return $total;
}

sub read_keepalive {
	my ($s) = @_;
	my $data = '';

	while (IO::Select->new($s)->can_read(3)) {
		sysread($s, my $buffer, 4096) or last;
		$data .= $buffer;
		last if $data =~ /^\x0d\x0a/ms;
	}

	log_in($data);
	return $data;
}

sub count_keepalive {
	my ($str) = @_;
	return $str =~ s/Connection: keep-alive//g;
}

###############################################################################
