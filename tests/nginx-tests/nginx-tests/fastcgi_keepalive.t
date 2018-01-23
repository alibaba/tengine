#!/usr/bin/perl

# (C) Maxim Dounin

# Test for fastcgi backend with keepalive.

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

my $t = Test::Nginx->new()->has(qw/http fastcgi upstream_keepalive/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream backend {
        server 127.0.0.1:8081;
        keepalive 1;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            fastcgi_pass backend;
            fastcgi_keep_conn on;
        }
    }
}

EOF

$t->run_daemon(\&fastcgi_test_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

like(http_get('/'), qr/SEE-THIS/, 'fastcgi request');
like(http_get('/redir'), qr/ 302 /, 'fastcgi redirect');
like(http_get('/'), qr/^request: 3$/m, 'fastcgi third request');

like(http_get('/single'), qr/^connection: 1$/m, 'single connection used');

# New connection to fastcgi application should be established after HEAD
# requests since nginx doesn't read whole response (as it doesn't need
# body).

unlike(http_head('/head'), qr/SEE-THIS/, 'no data in HEAD');

like(http_get('/after'), qr/^connection: 2$/m, 'new connection after HEAD');

###############################################################################

# Simple FastCGI responder implementation.  Unlike FCGI and FCGI::Async it's
# able to count connections.

# http://www.fastcgi.com/devkit/doc/fcgi-spec.html

sub fastcgi_read_record($) {
	my ($socket) = @_;

	my ($n, $h, $header);

	$n = $socket->read($header, 8);
	return undef if !defined $n or $n != 8;

	@{$h}{qw/ version type id clen plen /} = unpack("CCnnC", $header);

	$n = $socket->read($h->{content}, $h->{clen});
	return undef if $n != $h->{clen};

	$n = $socket->read($h->{padding}, $h->{plen});
	return undef if $n != $h->{plen};

	$h->{socket} = $socket;
	return $h;
}

sub fastcgi_respond($$) {
	my ($h, $body) = @_;

	# stdout
	$h->{socket}->write(pack("CCnnCx", $h->{version}, 6, $h->{id},
		length($body), 8));
	$h->{socket}->write($body);
	select(undef, undef, undef, 0.1);
	$h->{socket}->write(pack("xxxxxxxx"));
	select(undef, undef, undef, 0.1);

	# write some text to stdout and stderr split over multiple network
	# packets to test if we correctly set pipe length in various places

	my $tt = "test text, just for test";

	$h->{socket}->write(pack("CCnnCx", $h->{version}, 6, $h->{id},
		length($tt . $tt), 0) . $tt);
	select(undef, undef, undef, 0.1);
	$h->{socket}->write($tt . pack("CC", $h->{version}, 7));
	select(undef, undef, undef, 0.1);
	$h->{socket}->write(pack("nnCx", $h->{id}, length($tt), 0));
	select(undef, undef, undef, 0.1);
	$h->{socket}->write($tt);
	select(undef, undef, undef, 0.1);

	# close stdout
	$h->{socket}->write(pack("CCnnCx", $h->{version}, 6, $h->{id}, 0, 0));

	select(undef, undef, undef, 0.1);

	# end request
	$h->{socket}->write(pack("CCnnCx", $h->{version}, 3, $h->{id}, 8, 0));
	select(undef, undef, undef, 0.1);
	$h->{socket}->write(pack("NCxxx", 0, 0));
}

sub fastcgi_test_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	my $ccount = 0;
	my $rcount = 0;

	while (my $client = $server->accept()) {
		$client->autoflush(1);
		Test::Nginx::log_core('||', "fastcgi connection");

		$ccount++;

		while (my $h = fastcgi_read_record($client)) {
			Test::Nginx::log_core('||', "fastcgi record: "
				. " $h->{version}, $h->{type}, $h->{id}, "
				. "'$h->{content}'");

			# skip everything unless stdin, then respond
			next if $h->{type} != 5;

			$rcount++;

			# respond
			fastcgi_respond($h, <<EOF);
Location: http://localhost:8080/redirect
Content-Type: text/html

SEE-THIS
request: $rcount
connection: $ccount
EOF
		}

		$ccount-- unless $rcount;

		close $client;
	}
}

###############################################################################
