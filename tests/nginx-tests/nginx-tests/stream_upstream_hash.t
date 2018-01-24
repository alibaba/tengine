#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Stream tests for upstream hash balancer module.

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

my $t = Test::Nginx->new()->has(qw/stream stream_upstream_hash/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    upstream hash {
        hash $remote_addr;
        server 127.0.0.1:8087;
        server 127.0.0.1:8088;
    }

    upstream cons {
        hash $remote_addr consistent;
        server 127.0.0.1:8087;
        server 127.0.0.1:8088;
    }

    server {
        listen      127.0.0.1:8081;
        proxy_pass  hash;
    }

    server {
        listen      127.0.0.1:8082;
        proxy_pass  cons;
    }
}

EOF

$t->run_daemon(\&stream_daemon, 8087);
$t->run_daemon(\&stream_daemon, 8088);
$t->run();

$t->waitforsocket('127.0.0.1:8087');
$t->waitforsocket('127.0.0.1:8088');

###############################################################################

is(many('.', 10, peer => '127.0.0.1:8081'), '8088: 10', 'hash');
is(many('.', 10, peer => '127.0.0.1:8082'), '8088: 10', 'hash consistent');

###############################################################################

sub many {
	my ($data, $count, %opts) = @_;
	my (%ports, $peer);

	$peer = $opts{peer};

	for (1 .. $count) {
		if (stream($peer)->io($data) =~ /(\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	return join ', ', map { $_ . ": " . $ports{$_} } sort keys %ports;
}

###############################################################################

sub stream_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
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

	$buffer = $client->sockport();

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return 1;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
