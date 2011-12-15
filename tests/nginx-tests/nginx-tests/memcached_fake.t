#!/usr/bin/perl

# (C) Maxim Dounin

# Test for memcached backend with fake daemon.

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

my $t = Test::Nginx->new()->has(qw/http rewrite memcached ssi/)->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            set $memcached_key $uri;
            memcached_pass 127.0.0.1:8081;
        }

        location /ssi {
            default_type text/html;
            ssi on;
        }
    }
}

EOF

$t->write_file('ssi.html', '<!--#include virtual="/" set="blah" -->blah: <!--#echo var="blah" -->');
$t->run_daemon(\&memcached_fake_daemon);
$t->run();

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'memcached split trailer');

like(http_get('/ssi.html'), qr/SEE-THIS/, 'memcached ssi var');

like(`grep -F '[error]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no error');

###############################################################################

sub memcached_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if (/\x0d\x0a$/);
		}

		print $client 'VALUE / 0 8' . CRLF;
		print $client 'SEE-TH';
		select(undef, undef, undef, 0.1);
		print $client 'IS';
		select(undef, undef, undef, 0.1);
		print $client CRLF . 'EN';
		select(undef, undef, undef, 0.1);
		print $client 'D' . CRLF;
		close $client;
	}
}

###############################################################################
