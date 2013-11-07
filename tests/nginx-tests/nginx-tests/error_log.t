#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for error_log.
# Various log levels emitted with limit_req_log_level.

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

my $t = Test::Nginx->new()->has(qw/http limit_req/);

plan(skip_all => 'not yet') unless $t->has_version('1.5.2');
plan(skip_all => 'win32') if $^O eq 'MSWin32';

$t->plan(25)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    limit_req_zone $binary_remote_addr zone=one:10m rate=1r/m;
    limit_req zone=one;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /debug {
            error_log %%TESTDIR%%/e_debug_debug.log debug;
            error_log %%TESTDIR%%/e_debug_info.log info;
            error_log stderr debug;
        }
        location /info {
            limit_req_log_level info;
            error_log %%TESTDIR%%/e_info_debug.log debug;
            error_log %%TESTDIR%%/e_info_info.log info;
            error_log %%TESTDIR%%/e_info_notice.log notice;
            error_log stderr info;
        }
        location /notice {
            limit_req_log_level notice;
            error_log %%TESTDIR%%/e_notice_info.log info;
            error_log %%TESTDIR%%/e_notice_notice.log notice;
            error_log %%TESTDIR%%/e_notice_warn.log warn;
            error_log stderr notice;
        }
        location /warn {
            limit_req_log_level warn;
            error_log %%TESTDIR%%/e_warn_notice.log notice;
            error_log %%TESTDIR%%/e_warn_warn.log warn;
            error_log %%TESTDIR%%/e_warn_error.log error;
            error_log stderr warn;
        }
        location /error {
            error_log %%TESTDIR%%/e_error_warn.log warn;
            error_log %%TESTDIR%%/e_error_error.log;
            error_log %%TESTDIR%%/e_error_alert.log alert;
            error_log stderr;
        }

        location /file_low {
            error_log %%TESTDIR%%/e_multi_low.log warn;
            error_log %%TESTDIR%%/e_multi_low.log;
        }
        location /file_dup {
            error_log %%TESTDIR%%/e_multi.log;
            error_log %%TESTDIR%%/e_multi.log;
        }
        location /file_high {
            error_log %%TESTDIR%%/e_multi_high.log emerg;
            error_log %%TESTDIR%%/e_multi_high.log;
        }

        location /stderr_low {
            error_log stderr warn;
            error_log stderr;
        }
        location /stderr_dup {
            error_log stderr;
            error_log stderr;
        }
        location /stderr_high {
            error_log stderr emerg;
            error_log stderr;
        }
    }
}

EOF

open OLDERR, ">&", \*STDERR;
open STDERR, '>', $t->testdir() . '/stderr' or die "Can't reopen STDERR: $!";
open my $stderr, '<', $t->testdir() . '/stderr'
	or die "Can't open stderr file: $!";

$t->run();

open STDERR, ">&", \*OLDERR;

###############################################################################

# charge limit_req

http_get('/');

SKIP: {

skip "no --with-debug", 3 unless $t->has_module('--with-debug');

http_get('/debug');
isnt(lines($t, 'e_debug_debug.log', '[debug]'), 0, 'file debug debug');
is(lines($t, 'e_debug_info.log', '[debug]'), 0, 'file debug info');
isnt(lines($t, 'stderr', '[debug]'), 0, 'stderr debug');

}

http_get('/info');
is(lines($t, 'e_info_debug.log', '[info]'), 1, 'file info debug');
is(lines($t, 'e_info_info.log', '[info]'), 1, 'file info info');
is(lines($t, 'e_info_notice.log', '[info]'), 0, 'file info notice');
is(lines($t, 'stderr', '[info]'), 1, 'stderr info');

http_get('/notice');
is(lines($t, 'e_notice_info.log', '[notice]'), 1, 'file notice info');
is(lines($t, 'e_notice_notice.log', '[notice]'), 1, 'file notice notice');
is(lines($t, 'e_notice_warn.log', '[notice]'), 0, 'file notice warn');
is(lines($t, 'stderr', '[notice]'), 1, 'stderr notice');

http_get('/warn');
is(lines($t, 'e_warn_notice.log', '[warn]'), 1, 'file warn notice');
is(lines($t, 'e_warn_warn.log', '[warn]'), 1, 'file warn warn');
is(lines($t, 'e_warn_error.log', '[warn]'), 0, 'file warn error');
is(lines($t, 'stderr', '[warn]'), 1, 'stderr warn');

http_get('/error');
is(lines($t, 'e_error_warn.log', '[error]'), 1, 'file error warn');
is(lines($t, 'e_error_error.log', '[error]'), 1, 'file error error');
is(lines($t, 'e_error_alert.log', '[error]'), 0, 'file error alert');
is(lines($t, 'stderr', '[error]'), 1, 'stderr error');

# count log messages emitted with various error_log levels

http_get('/file_low');
is(lines($t, 'e_multi_low.log', '[error]'), 2, 'file low');

http_get('/file_dup');
is(lines($t, 'e_multi.log', '[error]'), 2, 'file dup');

http_get('/file_high');
is(lines($t, 'e_multi_high.log', '[error]'), 1, 'file high');

http_get('/stderr_low');
is(lines($t, 'stderr', '[error]'), 2, 'stderr low');

http_get('/stderr_dup');
is(lines($t, 'stderr', '[error]'), 2, 'stderr dup');

http_get('/stderr_high');
is(lines($t, 'stderr', '[error]'), 1, 'stderr high');

###############################################################################

sub lines {
	my ($t, $file, $pattern) = @_;

	if ($file eq 'stderr') {
		return map { $_ =~ /\Q$pattern\E/ } (<$stderr>);
	}

	my $path = $t->testdir() . '/' . $file;
	open my $fh, '<', $path or return "$!";
	my $value = map { $_ =~ /\Q$pattern\E/ } (<$fh>);
	close $fh;
	return $value;
}

###############################################################################
