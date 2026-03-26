#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for access_log.

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

my $t = Test::Nginx->new()->has(qw/http rewrite gzip/)->plan(19)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test "$uri:$status";
    log_format long "long line $uri:$status";
    log_format addr "$remote_addr:$remote_port:$server_addr:$server_port";
    log_format binary $binary_remote_addr;

    log_format default  escape=default  $uri$arg_b$arg_c;
    log_format none     escape=none     $uri$arg_b$arg_c;
    log_format json     escape=json     $uri$arg_b$arg_c;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /combined {
            access_log %%TESTDIR%%/combined.log;
            return 200 OK;

            location /combined/off {
                access_log off;
                return 200 OK;
            }
        }

        location /filtered {
            access_log %%TESTDIR%%/filtered.log test
                       if=$arg_logme;
            return 200 OK;
        }

        location /filtered/complex {
            access_log %%TESTDIR%%/complex.log test
                       if=$arg_logme$arg_logmetoo;
            return 200 OK;
        }

        location /filtered/noreuse {
            access_log %%TESTDIR%%/noreuse.log test buffer=16k
                       if=$arg_a;
            access_log %%TESTDIR%%/noreuse.log test buffer=16k
                       if=$arg_b;
            return 200 OK;
        }

        location /compressed {
            access_log %%TESTDIR%%/compressed.log test
                       gzip buffer=1m flush=100ms;
            return 200 OK;
        }

        location /multi {
            access_log %%TESTDIR%%/multi1.log test;
            access_log %%TESTDIR%%/multi2.log test;
            access_log %%TESTDIR%%/long.log long;
            return 200 OK;
        }

        location /varlog {
            access_log %%TESTDIR%%/varlog_${arg_logname} test;
            return 200 OK;
        }

        location /cache {
            open_log_file_cache max=3 inactive=20s valid=1m min_uses=2;
            access_log %%TESTDIR%%/dir/cache_${arg_logname} test;
            return 200 OK;
        }

        location /addr {
            access_log %%TESTDIR%%/addr.log addr;
        }

        location /binary {
            access_log %%TESTDIR%%/binary.log binary;
        }

        location /escape {
            access_log %%TESTDIR%%/test.log default;
            access_log %%TESTDIR%%/none.log none;
            access_log %%TESTDIR%%/json.log json;
        }
    }
}

EOF

my $d = $t->testdir();

mkdir "$d/dir";

$t->run();

###############################################################################

http_get('/combined');
http_get('/combined/off');

http_get('/filtered');
http_get('/filtered/empty?logme=');
http_get('/filtered/zero?logme=0');
http_get('/filtered/good?logme=1');
http_get('/filtered/work?logme=yes');

http_get('/filtered/complex');
http_get('/filtered/complex/one?logme=1');
http_get('/filtered/complex/two?logmetoo=1');
http_get('/filtered/complex/either1?logme=A&logmetoo=B');
http_get('/filtered/complex/either2?logme=A');
http_get('/filtered/complex/either3?logmetoo=B');
http_get('/filtered/complex/either4?logme=0&logmetoo=0');
http_get('/filtered/complex/neither?logme=&logmetoo=');

http_get('/filtered/noreuse1/zero?a=0');
http_get('/filtered/noreuse1/good?a=1');
http_get('/filtered/noreuse2/zero?b=0');
http_get('/filtered/noreuse2/good?b=1');

http_get('/compressed');

http_get('/multi');

http_get('/varlog');
http_get('/varlog?logname=');
http_get('/varlog?logname=0');
http_get('/varlog?logname=filename');

my $s = http('', start => 1);
my $addr = $s->sockhost();
my $port = $s->sockport();
my $saddr = $s->peerhost();
my $sport = $s->peerport();
http_get('/addr', socket => $s);

http_get('/binary');

# /escape/"1 %1B%1C "?c=2
http_get('/escape/%221%20%1B%1C%20%22?c=2');

http_get('/cache?logname=lru');
http_get('/cache?logname=lru');
http_get('/cache?logname=once');
http_get('/cache?logname=first');
http_get('/cache?logname=first');
http_get('/cache?logname=second');
http_get('/cache?logname=second');

rename "$d/dir", "$d/dir_moved";

http_get('/cache?logname=lru');
http_get('/cache?logname=once');
http_get('/cache?logname=first');
http_get('/cache?logname=second');

rename "$d/dir_moved",  "$d/dir";

# wait for file to appear with nonzero size thanks to the flush parameter

for (1 .. 10) {
	last if -s "$d/compressed.log";
	select undef, undef, undef, 0.1;
}

# verify that "gzip" parameter turns on compression

my $log;

SKIP: {
	eval { require IO::Uncompress::Gunzip; };
	skip("IO::Uncompress::Gunzip not installed", 1) if $@;

	my $gzipped = $t->read_file('compressed.log');
	IO::Uncompress::Gunzip::gunzip(\$gzipped => \$log);
	like($log, qr!^/compressed:200!s, 'compressed log - flush time');
}

# now verify all other logs

$t->stop();


# verify that by default, 'combined' format is used, 'off' disables logging

like($t->read_file('combined.log'),
	qr!^\Q$addr - - [\E .*
		\Q] "GET /combined HTTP/1.0" 200 2 "-" "-"\E$!x,
	'default log format');

# verify that log filtering works

$log = $t->read_file('filtered.log');
is($log, "/filtered/good:200\n/filtered/work:200\n", 'log filtering');

# verify "if=" argument works with complex value

my $exp_complex = <<'EOF';
/filtered/complex/one:200
/filtered/complex/two:200
/filtered/complex/either1:200
/filtered/complex/either2:200
/filtered/complex/either3:200
/filtered/complex/either4:200
EOF

is($t->read_file('complex.log'), $exp_complex, 'if with complex value');

# buffer created with false "if" is not reused among multiple access_log

$log = $t->read_file('noreuse.log');
is($log, "/filtered/noreuse1/good:200\n/filtered/noreuse2/good:200\n",
	'log filtering with buffering');

# multiple logs in a same location

is($t->read_file('multi1.log'), "/multi:200\n", 'multiple logs 1');

# same content in the second log

is($t->read_file('multi2.log'), "/multi:200\n", 'multiple logs 2');

is($t->read_file('long.log'), "long line /multi:200\n", 'long line format');

# test log destinations with variables

is($t->read_file('varlog_0'), "/varlog:200\n", 'varlog literal zero name');
is($t->read_file('varlog_filename'), "/varlog:200\n", 'varlog good name');

is($t->read_file('addr.log'), "$addr:$port:$saddr:$sport\n", 'addr');

# binary data is escaped
# that's "\\x7F\\x00\\x00\\x01\n" in $binary_remote_addr for "127.0.0.1"

my $expected = join '', map { sprintf "\\x%02X", $_ } split /\./, $addr;

is($t->read_file('binary.log'), "$expected\n", 'binary');

# characters escaping

is($t->read_file('test.log'),
	'/escape/\x221 \x1B\x1C \x22-2' . "\n", 'escape - default');
is($t->read_file('none.log'),
	"/escape/\"1 \x1B\x1C \"2\n", 'escape - none');
is($t->read_file('json.log'),
	'/escape/\"1 \u001B\u001C \"2' . "\n", 'escape - json');

SKIP: {
skip 'win32', 4 if $^O eq 'MSWin32';

is(@{[$t->read_file('/dir/cache_lru') =~ /\//g]}, 2, 'cache - closed lru');
is(@{[$t->read_file('/dir/cache_once') =~ /\//g]}, 1, 'cache - min_uses');
is(@{[$t->read_file('/dir/cache_first') =~ /\//g]}, 3, 'cache - cached 1');
is(@{[$t->read_file('/dir/cache_second') =~ /\//g]}, 3, 'cache - cached 2');

}

###############################################################################
