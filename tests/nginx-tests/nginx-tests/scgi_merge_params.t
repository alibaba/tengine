#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for scgi_param inheritance.

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

eval { require SCGI; };
plan(skip_all => 'SCGI not installed') if $@;

my $t = Test::Nginx->new()->has(qw/http scgi cache/)->plan(9)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    scgi_cache_path  %%TESTDIR%%/cache  levels=1:2
                     keys_zone=NAME:10m;

    scgi_param SCGI 1;
    scgi_param HTTP_X_BLAH "blah";

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        scgi_cache  NAME;

        location / {
            scgi_pass    127.0.0.1:8081;
        }

        location /no/ {
            scgi_pass    127.0.0.1:8081;
            scgi_cache   off;
        }

        location /custom/ {
            scgi_pass    127.0.0.1:8081;
            scgi_param   SCGI 1;
            scgi_param   HTTP_X_BLAH  "custom";
        }
    }
}

EOF

$t->run_daemon(\&scgi_daemon);
$t->run();

###############################################################################

like(http_get_ims('/'), qr/ims=;/,
	'if-modified-since cleared with cache');

TODO: {
local $TODO = 'not yet';

like(http_get_ims('/'), qr/iums=;/,
	'if-unmodified-since cleared with cache');

}

like(http_get_ims('/'), qr/blah=blah;/,
	'custom params with cache');

TODO: {
local $TODO = 'not yet';

like(http_get_ims('/no/'), qr/ims=blah;/,
	'if-modified-since preserved without cache');

}

like(http_get_ims('/no/'), qr/iums=blah;/,
	'if-unmodified-since preserved without cache');
like(http_get_ims('/'), qr/blah=blah;/,
	'custom params without cache');

like(http_get_ims('/custom/'), qr/ims=;/,
	'if-modified-since cleared with cache custom');

TODO: {
local $TODO = 'not yet';

like(http_get_ims('/custom/'), qr/iums=;/,
	'if-unmodified-since cleared with cache custom');
}

like(http_get_ims('/custom/'), qr/blah=custom;/,
	'custom params with cache custom');

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

sub scgi_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $scgi = SCGI->new($server, blocking => 1);
	my $count = 0;
  
	while (my $request = $scgi->accept()) {
		$count++;
		$request->read_env();

		my $ims = $request->env->{HTTP_IF_MODIFIED_SINCE} || '';
		my $iums = $request->env->{HTTP_IF_UNMODIFIED_SINCE} || '';
		my $blah = $request->env->{HTTP_X_BLAH} || '';

		$request->connection()->print(<<EOF);
Location: http://127.0.0.1:8080/redirect
Content-Type: text/html

ims=$ims;iums=$iums;blah=$blah;
EOF
	}
}

###############################################################################
