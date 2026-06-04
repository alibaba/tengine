#!/usr/bin/perl

# Regression test for CVE-2026-42945.
#
# When a rewrite directive places a regex capture into the query-string
# part (e.g. "rewrite ^/x/(.*) /y?p=$1"), the script engine sets the
# is_args flag while emitting the captured bytes.  Prior to the fix,
# ngx_http_script_regex_end_code() did not clear is_args at the end of
# the rewrite, so the flag leaked into any subsequent rewrite/script
# block executed within the same location.  The next capture copy then
# went through ngx_escape_uri(NGX_ESCAPE_ARGS), double-escaping bytes
# that belong to the URI path.  The fix resets e->is_args = 0 in
# ngx_http_script_regex_end_code(), mirroring the existing e->quote
# reset.
#
# These tests fail without the fix because the second rewrite's path
# capture is incorrectly ARGS-escaped (e.g. "%" -> "%25", " " -> "%20").

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # Baseline: a single rewrite with a capture in the args part.
        # Used to confirm the "args capture is ARGS-escaped" half of
        # the existing behavior is unchanged.
        location /single {
            rewrite ^/single(/.*) /done$1?p=test;
            return 200 "uri:$uri args:$args";
        }

        # CVE-2026-42945 reproducer: two rewrites in the same location.
        # The first rewrite puts a capture into the args part, which
        # makes the engine flip is_args=1.  The second rewrite has the
        # capture in the path part and must NOT be ARGS-escaped.
        location /leak {
            rewrite ^/leak(/.*) /mid$1?p=test;
            rewrite ^/mid(/.*)  /final$1;
            return 200 "uri:$uri args:$args";
        }

        # Same as /leak but the inbound request contains neither %xx
        # escapes nor "+", so both r->quoted_uri and r->plus_in_uri
        # stay 0.  ngx_http_script_copy_capture_code() never enters
        # the ARGS-escape branch even if is_args leaks, so this case
        # passes regardless of the fix.  Kept to guard against the
        # fix accidentally over-escaping clean requests.
        location /clean {
            rewrite ^/clean(/.*) /mid$1?p=test;
            rewrite ^/mid(/.*)   /final$1;
            return 200 "uri:$uri args:$args";
        }
    }
}

EOF

$t->run();

###############################################################################

# Baseline: capture in args is ARGS-escaped because the request URI
# was %xx-encoded (r->quoted_uri == 1).  "%" must become "%25" in args.
like(http_get('/single/%25'),
	qr!^uri:/done/% args:p=test$!ms,
	'baseline: single rewrite, args part untouched in $args var');

# Baseline 2: with a space in the args capture, the args still hold
# the un-escaped value because $args is the raw rewritten string.
like(http_get('/single/%20'),
	qr!^uri:/done/  args:p=test$!ms,
	'baseline: single rewrite with space, path capture not escaped');

# CVE-2026-42945 core: the second rewrite's path capture must keep
# the unescaped "%" byte.  Without the fix is_args leaks and the
# capture is re-escaped to "%25".
like(http_get('/leak/%25'),
	qr!^uri:/final/% args:p=test$!ms,
	'CVE-2026-42945: percent in path capture not re-escaped');

# Same, with a space.  Without the fix the leaked is_args turns the
# space back into "%20" because NGX_ESCAPE_ARGS escapes spaces.
like(http_get('/leak/%20'),
	qr!^uri:/final/  args:p=test$!ms,
	'CVE-2026-42945: space in path capture not re-escaped');

# Same CVE, triggered via r->plus_in_uri instead of r->quoted_uri:
# a literal "+" in the request path also flips the plus_in_uri flag,
# which (combined with leaked is_args) makes the second rewrite's
# capture get ARGS-escaped, turning "+" into "%2B".
like(http_get('/leak/a+b'),
	qr!^uri:/final/a\+b args:p=test$!ms,
	'CVE-2026-42945: plus in path capture not re-escaped');

# Control: no %xx and no "+" in the inbound request, so neither
# quoted_uri nor plus_in_uri is set.  The bug is unobservable here;
# this test mainly guards against the fix accidentally regressing
# the clean path.
like(http_get('/clean/abc'),
	qr!^uri:/final/abc args:p=test$!ms,
	'unencoded request: path capture stays intact');

###############################################################################
