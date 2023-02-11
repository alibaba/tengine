#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream realip module, server side proxy protocol.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_return stream_realip/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen      127.0.0.1:8083 proxy_protocol;
        listen      127.0.0.1:8084;
        return      $proxy_protocol_addr:$proxy_protocol_port;
    }

    server {
        listen      127.0.0.1:8085 proxy_protocol;
        proxy_pass  127.0.0.1:8081;
    }

    server {
        listen      127.0.0.1:8086 proxy_protocol;
        listen      [::1]:%%PORT_8086%% proxy_protocol;
        return      "$remote_addr:$remote_port:
                     $realip_remote_addr:$realip_remote_port";

        set_real_ip_from ::1;
        set_real_ip_from 127.0.0.2;
    }

    server {
        listen      127.0.0.1:8087;
        proxy_pass  [::1]:%%PORT_8086%%;
    }

    server {
        listen      127.0.0.1:8088 proxy_protocol;
        listen      [::1]:%%PORT_8088%% proxy_protocol;
        return      "$remote_addr:$remote_port:
                     $realip_remote_addr:$realip_remote_port";

        set_real_ip_from 127.0.0.1;
        set_real_ip_from ::2;
    }

    server {
        listen      127.0.0.1:8089;
        proxy_pass  [::1]:%%PORT_8088%%;
    }
}

EOF

$t->run_daemon(\&stream_daemon);
$t->try_run('no inet6 support')->plan(8);
$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

is(pp_get(8083, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	'192.0.2.1:1234', 'server');

is(stream('127.0.0.1:' . port(8084))->read(), ':', 'server off');

is(pp_get(8085, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}close"),
	'close', 'server payload');

like(pp_get(8086, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(\Q127.0.0.1:\E\d+):\s+\1$/, 'server ipv6 realip - no match');

like(pp_get(8087, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/\Q192.0.2.1:1234:\E\s+\Q::1:\E\d+/, 'server ipv6 realip');

like(pp_get(8088, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/\Q192.0.2.1:1234:\E\s+\Q127.0.0.1:\E\d+/, 'server ipv4 realip');

like(pp_get(8089, "PROXY TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(::1:\d+):\s+\1$/, 'server ipv4 realip - no match');

like(pp_get(8088, "PROXY UNKNOWN TCP4 192.0.2.1 192.0.2.2 1234 5678${CRLF}"),
	qr/^(\Q127.0.0.1:\E\d+):\s+\1$/, 'server unknown');

###############################################################################

sub pp_get {
	my ($port, $proxy) = @_;
	stream(PeerPort => port($port))->io($proxy);
}

###############################################################################

sub stream_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1:' . port(8081),
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

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $buffer =~ /close/;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
