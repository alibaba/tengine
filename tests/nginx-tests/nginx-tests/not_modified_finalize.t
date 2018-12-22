#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for not modified filter and filter finalization.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(1)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path %%TESTDIR%%/cache keys_zone=cache:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        error_page 412 /error412.html;

        location / {
            proxy_pass        http://127.0.0.1:8081;
            proxy_cache       cache;
            proxy_cache_lock  on;
        }

        location /error412 {
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
    }
}

EOF

$t->write_file('t.html', 'test file');
$t->write_file('error412.html', 'error412');

$t->run();

###############################################################################

# we trigger filter finalization in not modified filter by using
# the If-Unmodified-Since/If-Match header;
# with cache enabled and updating bit set, this currently results in
# "stalled cache updating" alerts

like(http_match_get('/t.html'), qr//, 'request 412');

$t->todo_alerts();

###############################################################################

sub http_match_get {
	my ($url, %extra) = @_;
	return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: localhost
If-Match: tt

EOF
}

###############################################################################
