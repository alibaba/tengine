#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for http proxy cache lock.

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http proxy cache/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:10m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
        }

        location /timeout {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
            proxy_cache_lock_timeout 300ms;
        }

        location /nolock {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;
        }
    }
}

EOF

$t->run_daemon(\&http_fake_daemon);

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no proxy_cache_lock') if $@;

$t->plan(19);
$t->waitforsocket('127.0.0.1:8081');

###############################################################################

# sequentional requests

for my $i (1 .. 5) {
	like(http_get('/seq'), qr/request 1/, 'sequentional request ' . $i);
}

# parallel requests

my @sockets;

for my $i (1 .. 5) {
	$sockets[$i] = http_start('/par1');
}

for my $i (1 .. 5) {
	like(http_end($sockets[$i]), qr/request 1/, 'parallel request ' . $i);
}

like(http_get('/par1'), qr/request 1/, 'first request cached');

# parallel requests with cache lock timeout

for my $i (1 .. 3) {
	$sockets[$i] = http_start('/timeout');
}

for my $i (1 .. 3) {
	like(http_end($sockets[$i]), qr/request $i/, 'lock timeout ' . $i);
}

like(http_get('/timeout'), qr/request 3/, 'lock timeout - last cached');

# no lock

for my $i (1 .. 3) {
	$sockets[$i] = http_start('/nolock');
}

for my $i (1 .. 3) {
	like(http_end($sockets[$i]), qr/request $i/, 'nolock  ' . $i);
}

like(http_get('/nolock'), qr/request 3/, 'nolock - last cached');

###############################################################################

sub http_start {
	my ($uri) = @_;

	my $s;
	my $request = "GET $uri HTTP/1.0" . CRLF . CRLF;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:8080'
		);
		log_out($request);
		$s->print($request);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}
	return $s;
}

sub http_end {
	my ($s) = @_;
	my $reply;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		local $/;
		$reply = $s->getline();
		log_in($reply);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}
	return $reply;
}

###############################################################################

sub http_fake_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $num = 0;
	my $uri = '';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			if (/GET (.*) HTTP/ && $1 ne $uri) {
				$uri = $1;
				$num = 0;
			}

			$uri = $1 if /GET (.*) HTTP/;
			last if /^\x0d?\x0a?$/;
		}

		next unless $uri;

		sleep(1);

		$num++;
		print $client <<"EOF";
HTTP/1.1 200 OK
Cache-Control: max-age=300
Connection: close

request $num
EOF
	}
}

###############################################################################
