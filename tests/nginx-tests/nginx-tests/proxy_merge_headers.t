#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for proxy_set_header inheritance.

###############################################################################

use warnings;
use strict;

use Test::More;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy cache rewrite/)->plan(11)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    proxy_set_header X-Blah "blah";
    proxy_hide_header X-Hidden;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_cache  NAME;

        location / {
            proxy_pass    http://127.0.0.1:8081;

            location /nested/ {
                proxy_pass   http://127.0.0.1:8081;
                proxy_pass_header X-Pad;
            }
        }

        location /no/ {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   off;
        }

        location /setbody/ {
            proxy_pass    http://127.0.0.1:8081;
            proxy_set_body "body";
        }

        location /passdate/ {
            proxy_pass    http://127.0.0.1:8082;
            proxy_pass_header Date;
            proxy_pass_header Server;

            location /passdate/no/ {
                proxy_pass   http://127.0.0.1:8082;
            }
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Hidden "hidden";
            add_header X-Pad "passed";
            return 200 "ims=$http_if_modified_since;blah=$http_x_blah;";
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8082));

###############################################################################

like(http_get_ims('/'), qr/ims=;blah=blah;/,
	'if-modified-since cleared with cache');

like(http_get_ims('/no/'), qr/ims=blah;blah=blah;/,
	'if-modified-since preserved without cache');

like(http_get_ims('/setbody/'), qr/blah=blah;/,
	'proxy_set_header inherited with proxy_set_body');

unlike(http_get('/'), qr/X-Pad/, 'proxy_pass_header default');
like(http_get('/nested/'), qr/X-Pad/, 'proxy_pass_header nested');
unlike(http_get('/'), qr/X-Hidden/, 'proxy_hide_header inherited');
unlike(http_get('/nested/'), qr/X-Hidden/, 'proxy_hide_header nested');

like(http_get('/passdate/'), qr/Date: passed/, 'proxy_pass_header date');
like(http_get('/passdate/'), qr/Server: passed/, 'proxy_pass_header server');
unlike(http_get('/passdate/no/'), qr/Date/, 'proxy_pass_header no date');
unlike(http_get('/passdate/no/'), qr/Server/, 'proxy_pass_header no server');

###############################################################################

sub http_get_ims {
	my ($url) = @_;
	return http(<<EOF);
GET $url HTTP/1.0
Host: localhost
Connection: close
If-Modified-Since: blah

EOF
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8082),
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

		if ($uri =~ 'no') {
			print $client
				'HTTP/1.0 200 OK' . CRLF . CRLF;

		} else {
			print $client
				'HTTP/1.0 200 OK' . CRLF .
				'Date: passed' . CRLF .
				'Server: passed' . CRLF . CRLF;
		}

		close $client;
	}
}

###############################################################################
