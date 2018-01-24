#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module.

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

my $t = Test::Nginx->new()->has(qw/stream/)->plan(5)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    server {
        listen      127.0.0.1:8080;
        proxy_pass  127.0.0.1:8081;
        proxy_connect_timeout 2s;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->run()->waitforsocket('127.0.0.1:8081');

###############################################################################

my $s = stream();

is($s->io('foo1', length => 4), 'bar1', 'proxy connection');
is($s->io('foo3', length => 4), 'bar3', 'proxy connection again');
is($s->io('close'), 'close', 'proxy connection close');
is($s->io('test'), '', 'proxy connection closed');

$s = stream();

sleep 3;

is($s->io('foo', length => 3), 'bar', 'proxy connect timeout');

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:8081',
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

	$buffer =~ s/foo/bar/g;

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $buffer =~ /close/;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
