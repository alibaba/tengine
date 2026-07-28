#!/usr/bin/perl

# (C) Vinay Kumar Tokala
# (C) Nginx, Inc.

# Tests for stripping connection-specific headers from proxied responses.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v2 map proxy/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        http2 on;

        location / {
            proxy_pass http://127.0.0.1:8081;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon);
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# preserve Upgrade for HTTP/1.1 client

like(get('/upgrade200'), qr/ 200 .*^Upgrade/msi, 'upgrade in 200');
like(get('/upgrade426'), qr/ 426 .*^Upgrade/msi, 'upgrade in 426');
like(get('/upgrade101', Upgrade => 'websocket', Connection => 'Upgrade'),
	qr/ 101 .*^Upgrade/msi, 'upgrade in 101');

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.31.3');

# strip Upgrade for HTTP/2 client

is(h2_get('/upgrade200'), '200 0', 'upgrade stripped in HTTP/2 200');
is(h2_get('/upgrade426'), '426 0', 'upgrade stripped in HTTP/2 426');

}

###############################################################################

sub get {
	my ($uri, %extra) = @_;
	my $headers = '';
	for my $h (sort keys %extra) {
		$headers .= "$h: $extra{$h}" . CRLF;
	}
	$headers .= 'Connection: close' . CRLF unless $extra{Connection};
	return http(
		'GET ' . $uri . ' HTTP/1.1' . CRLF
		. 'Host: localhost' . CRLF
		. $headers
		. CRLF
	);
}

sub h2_get {
	my ($path) = @_;
	my $s = Test::Nginx::HTTP2->new();
	my $sid = $s->new_stream({ path => $path });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
	my ($frame) = grep { $_->{type} eq 'HEADERS' } @$frames;
	my $status = $frame->{headers}->{':status'};
	my $upgrade = defined $frame->{headers}->{'upgrade'} ? 1 : 0;
	return "$status $upgrade";
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => port(8081),
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

		next if $headers eq '';
		$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

		if ($uri eq '/upgrade200') {

			print $client
				'HTTP/1.1 200 OK' . CRLF .
				'Connection: Upgrade' . CRLF .
				'Upgrade: websocket' . CRLF .
				CRLF;

		} elsif ($uri eq '/upgrade426') {

			print $client
				'HTTP/1.1 426 Upgrade Required' . CRLF .
				'Connection: Upgrade' . CRLF .
				'Upgrade: websocket' . CRLF .
				CRLF;

		} elsif ($uri eq '/upgrade101') {

			print $client
				'HTTP/1.1 101 Switching Protocols' . CRLF .
				'Upgrade: websocket' . CRLF .
				'Connection: Upgrade' . CRLF .
				CRLF;

		} else {

			print $client
				'HTTP/1.1 404 Not Found' . CRLF .
				CRLF;
		}
	}
}

###############################################################################
