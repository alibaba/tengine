#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stub status module.

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

my $t = Test::Nginx->new()->has(qw/http stub_status/)->plan(34);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        add_header X-Active $connections_active;
        add_header X-Reading $connections_reading;
        add_header X-Writing $connections_writing;
        add_header X-Waiting $connections_waiting;

        location / { }
        location /rate {
            limit_rate 15;
        }
        location /stub {
            stub_status;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

my %status = status('/stub');
like(http_get('/stub'), qr/200 OK/, 'get request');
is($status{'active'}, 1, 'open connection');
is($status{'requests'}, 1, 'first request');
is($status{'accepts'}, 1, 'first request accepted');
is($status{'handled'}, 1, 'first request handled');
is($status{'writing'}, 1, 'first response');
is($status{'reading'}, 0, 'not reading');

# pipelined requests

http(<<EOF);
GET / HTTP/1.1
Host: localhost

GET / HTTP/1.1
Host: localhost
Connection: close

EOF

%status = status('/stub');
is($status{'requests'}, 5, 'requests increased by 2');
is($status{'accepts'}, 4, 'accepts increased by 1');

# states

my $s = http('', start => 1);

%status = status('/stub');
is($status{'active'}, 2, 'active');
is($status{'waiting'}, 1, 'waiting state');
is($status{'reading'}, 0, 'waiting state - not reading');
is($status{'writing'}, 1, 'waiting state - not writing');

http(<<EOF, start => 1, socket => $s, sleep => 0.2);
GET /rate HTTP/1.0
EOF

%status = status('/stub');
is($status{'waiting'}, 0, 'reading state - not waiting');
is($status{'reading'}, 1, 'reading state');
is($status{'writing'}, 1, 'reading state - not writing');

http(<<EOF, start => 1, socket => $s, sleep => 0.2);
Host: localhost

EOF

%status = status('/stub');
is($status{'waiting'}, 0, 'writing state - not waiting');
is($status{'reading'}, 0, 'writing state - not reading');
is($status{'writing'}, 2, 'writing state');

$s->close();

# head and post requests

like(http_head('/stub'), qr/200 OK/, 'head request');
like(http_post('/stub'), qr/405 Not Allowed/, 'post request');

# embedded variables in headers

my $r = http_get('/stub');
like($r, qr/X-Active: 1/, 'get - var active');
like($r, qr/X-Reading: 0/, 'get - var reading');
like($r, qr/X-Writing: 1/, 'get - var writing');
like($r, qr/X-Waiting: 0/, 'get - var waiting');

$r = http_head('/stub');
like($r, qr/X-Active: 1/, 'head - var active');
like($r, qr/X-Reading: 0/, 'head - var reading');
like($r, qr/X-Writing: 1/, 'head - var writing');
like($r, qr/X-Waiting: 0/, 'head - var waiting');
is(get_body($r), '', 'head - empty body');

$r = http_get('/');
like($r, qr/X-Active: 1/, 'no stub - var active');
like($r, qr/X-Reading: 0/, 'no stub - var reading');
like($r, qr/X-Writing: 1/, 'no stub - var writing');
like($r, qr/X-Waiting: 0/, 'no stub - var waiting');

###############################################################################

sub get_body {
	my ($r) = @_;
	$r =~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;
	return $1;
}

sub http_post {
	my ($url) = @_;
	return http(<<EOF);
POST $url HTTP/1.0
Host: localhost

EOF
}

sub status {
	my ($url) = @_;
	my $r = http_get($url);

	$r =~ /
		Active\ connections:\ +(\d+)
		\s+server\ accepts\ handled\ requests
		\s+(\d+)\ +(\d+)\ +(\d+)
		\s+Reading:\ +(\d+)
		\s+Writing:\ +(\d+)
		\s+Waiting:\ +(\d+)
	/sx;

	return ('active' => $1,
		'accepts' => $2,
		'handled' => $3,
		'requests' => $4,
		'reading' => $5,
		'writing' => $6,
		'waiting' => $7,
	);
}

###############################################################################
