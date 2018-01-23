#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for tcp_nodelay.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream/);

plan(skip_all => 'no tcp_nodelay') unless $t->has_version('1.9.4');

$t->plan(2)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    proxy_buffer_size 1;
    tcp_nodelay off;

    server {
        listen      127.0.0.1:8081;
        proxy_pass  127.0.0.1:8080;
    }

    server {
        tcp_nodelay on;
        listen      127.0.0.1:8082;
        proxy_pass  127.0.0.1:8080;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->run()->waitforsocket('127.0.0.1:8080');

###############################################################################

my $str = '1234567890' x 10 . 'F';
my $length = length($str);

is(stream('127.0.0.1:8081')->io($str, length => $length), $str,
	'tcp_nodelay off');
is(stream('127.0.0.1:8082')->io($str, length => $length), $str,
	'tcp_nodelay on');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8080',
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($server == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

	log2i("$client $buffer");

	my $close = $buffer =~ /F/;

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $close;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
