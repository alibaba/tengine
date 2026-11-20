#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for dubbo_pass decoding hessian2 binary ("[B") values from a backend
# response, the path that feeds hessian2_output::write_bytes() on the way back
# out. Report #2118 claimed write_bytes() reads out of bounds because it trusts
# its length argument; it does not scan the buffer, so it copies exactly that
# many bytes, and the only caller passes a std::string's own (data, size). A
# backend cannot break that: a binary whose announced length exceeds the bytes
# present is rejected by the decoder before any ByteArray is built. Each such
# response must end in a 502, with the worker left running, and a well-formed
# binary body -- arbitrary bytes, not UTF-8 -- must round-trip.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;
use IO::Socket::INET;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http mod_dubbo ngx_multi_upstream_module/)->plan(6)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    # One upstream per case, so that every case gets a connection of its own
    # and the decoder works on a payload buffer sized for that response alone:
    # a read past its end then leaves the allocation, which a sanitizer build
    # reports.

    upstream u_ok {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_over_long {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_over_chunk {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    server {
        listen       127.0.0.1:%%PORT_8080%%;
        server_name  localhost;

        location /ok {
            dubbo_pass test.Service 1.0.0 m_ok u_ok;
        }

        location /over_long {
            dubbo_pass test.Service 1.0.0 m_over_long u_over_long;
        }

        location /over_chunk {
            dubbo_pass test.Service 1.0.0 m_over_chunk u_over_chunk;
        }
    }
}

EOF

$t->run_daemon(\&dubbo_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# a well-formed binary body of arbitrary, non-UTF-8 bytes round-trips
like(http_get('/ok'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0a\x80\x81\xfe\xff$!s,
	'well-formed binary body');

# a final-chunk binary 'B' announcing 32 bytes but carrying one, at the very
# end of the payload: the decoder rejects the length before a ByteArray exists
like(http_get('/over_long'), qr!^HTTP/1\.1 502 !,
	'binary longer than the payload');

# the same over a non-final 'A' chunk
like(http_get('/over_chunk'), qr!^HTTP/1\.1 502 !,
	'chunked binary longer than the payload');

like(http_get('/ok'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0a\x80\x81\xfe\xff$!s,
	'well-formed binary body after the failures');

$t->stop();

my $log = $t->read_file('error.log');

my @over = $log =~ /parse exception failed .*read_raw_bytes\(\): will reach EOF/g;
is(scalar @over, 2, 'oversized binary lengths rejected where the payload ends');

unlike($log, qr/exited on signal/, 'no worker crashed');

###############################################################################

# A Dubbo provider that answers every request with the payload chosen by the
# method name found in it, under the request id it came with.

sub dubbo_daemon {
	my ($port) = @_;

	# hessian2 response payloads: the RESPONSE_VALUE flag as an int, then
	# the value
	my $flag = "I\x00\x00\x00\x01";

	my %replies = (

		# { "body": b"\x80\x81\xfe\xff", "status": "200" } -- a final 'B'
		# chunk whose announced length matches the four bytes present
		m_ok => $flag . 'H'
			. "\x04" . 'body' . "B\x00\x04" . "\x80\x81\xfe\xff"
			. "\x06" . 'status' . "\x03" . '200'
			. 'Z',

		# { "body": <binary announcing 32 bytes, carrying one> }, with the
		# payload ending right after that one byte
		m_over_long => $flag . 'H'
			. "\x04" . 'body' . "B\x00\x20" . 'A',

		# the same, but over a non-final 'A' chunk
		m_over_chunk => $flag . 'H'
			. "\x04" . 'body' . "A\x00\x20" . 'A',
	);

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	my $sel = IO::Select->new($server);
	my %in;

	while (my @ready = $sel->can_read()) {
		foreach my $fh (@ready) {
			if ($fh == $server) {
				my $client = $server->accept() or next;
				$client->autoflush(1);
				$sel->add($client);
				$in{$client} = '';
				next;
			}

			my $n = $fh->sysread(my $buf, 65536);

			if (!$n) {
				$sel->remove($fh);
				delete $in{$fh};
				$fh->close();
				next;
			}

			$in{$fh} .= $buf;

			# header: magic(2) flag(1) status(1) id(8) payload length(4)
			while (length($in{$fh}) >= 16) {
				my ($flags, $id, $len) = unpack('x2 C x a8 N', $in{$fh});
				last if length($in{$fh}) < 16 + $len;

				my $payload = substr($in{$fh}, 16, $len);
				substr($in{$fh}, 0, 16 + $len) = '';

				# heartbeats need no answer
				next if $flags & 0x20;

				my ($method) = $payload =~
					/(m_(?:ok|over_long|over_chunk))/;
				next unless defined $method;

				my $reply = $replies{$method};

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02, 20, $id,
					length($reply)) . $reply);
			}
		}
	}
}

###############################################################################
