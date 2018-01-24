#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for fastcgi_param inheritance.

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

eval { require FCGI; };
plan(skip_all => 'FCGI not installed') if $@;
plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http fastcgi cache shmem/)->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    fastcgi_cache_path  %%TESTDIR%%/cache  levels=1:2
                        keys_zone=NAME:1m;

    fastcgi_cache_key   stub;

    # no fastcgi_param at all, cache switched on at server level

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        fastcgi_cache  NAME;

        location / {
            fastcgi_pass    127.0.0.1:8081;
        }

        location /no/ {
            fastcgi_pass    127.0.0.1:8081;
            fastcgi_cache   off;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get_ims('/'), qr/ims=;/,
	'if-modified-since cleared with cache');
like(http_get_ims('/'), qr/iums=;/,
	'if-unmodified-since cleared with cache');

like(http_get_ims('/no/'), qr/ims=blah;/,
	'if-modified-since preserved without cache');
like(http_get_ims('/no/'), qr/iums=blah;/,
	'if-unmodified-since preserved without cache');

###############################################################################

sub http_get_ims {
	my ($url) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Connection: close
If-Modified-Since: blah
If-Unmodified-Since: blah

EOF
}

###############################################################################

sub fastcgi_daemon {
	my $socket = FCGI::OpenSocket('127.0.0.1:8081', 5);
	my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
		$socket);

	my $count;
	while( $request->Accept() >= 0 ) {
		$count++;

		my $ims = $ENV{HTTP_IF_MODIFIED_SINCE};
		my $iums = $ENV{HTTP_IF_UNMODIFIED_SINCE};
		my $blah = $ENV{HTTP_X_BLAH};

		print <<EOF;
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html

ims=$ims;iums=$iums;blah=$blah;
EOF
	}

	FCGI::CloseSocket($socket);
}

###############################################################################
