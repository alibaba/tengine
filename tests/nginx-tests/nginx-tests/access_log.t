#!/usr/bin/perl

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(9)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    log_format test "$uri:$status";

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
            return 200 OK;
        }

        location /varlog {
            access_log %%TESTDIR%%/varlog_${arg_logname} test;
            return 200 OK;
        }
    }
}

EOF

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


# wait for file to appear with nonzero size thanks to the flush parameter

for (1 .. 10) {
	last if -s $t->testdir() . '/compressed.log';
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

my $addr = IO::Socket::INET->new(LocalAddr => '127.0.0.1')->sockhost();

$log = $t->read_file('combined.log');
like($log,
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

$log = $t->read_file('complex.log');
is($log, $exp_complex, 'if with complex value');


# buffer created with false "if" is not reused among multiple access_log

$log = $t->read_file('/noreuse.log');
is($log, "/filtered/noreuse1/good:200\n/filtered/noreuse2/good:200\n",
	'log filtering with buffering');


# multiple logs in a same location

$log = $t->read_file('multi1.log');
is($log, "/multi:200\n", 'multiple logs 1');

# same content in the second log

$log = $t->read_file('multi2.log');
is($log, "/multi:200\n", 'multiple logs 2');


# test log destinations with variables

$log = $t->read_file('varlog_0');
is($log, "/varlog:200\n", 'varlog literal zero name');

$log = $t->read_file('varlog_filename');
is($log, "/varlog:200\n", 'varlog good name');

###############################################################################
