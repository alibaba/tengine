#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for dubbo_pass decoding hessian2 strings from a backend response whose
# multi-byte UTF-8 chars run past the end of the payload, and for decoding
# failures inside the Exception deserializer. Neither may read past the
# payload or free memory the decoder does not own: each such response must
# end in a 502, with the worker left running.

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
	->has(qw/http mod_dubbo ngx_multi_upstream_module/)->plan(9)
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

    upstream u_cut_value {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_cut_key {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_short_key {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_short_detail {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    server {
        listen       127.0.0.1:%%PORT_8080%%;
        server_name  localhost;

        location /ok {
            dubbo_pass test.Service 1.0.0 m_ok u_ok;
        }

        location /cut_value {
            dubbo_pass test.Service 1.0.0 m_cut_value u_cut_value;
        }

        location /cut_key {
            dubbo_pass test.Service 1.0.0 m_cut_key u_cut_key;
        }

        location /short_key {
            dubbo_pass test.Service 1.0.0 m_short_key u_short_key;
        }

        location /short_detail {
            dubbo_pass test.Service 1.0.0 m_short_detail u_short_detail;
        }
    }
}

EOF

$t->run_daemon(\&dubbo_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed response');

# a map value whose last char is a 3-byte lead with no continuation bytes
like(http_get('/cut_value'), qr!^HTTP/1\.1 502 !, 'value cut inside a char');

# the same in a key read by the Exception deserializer
like(http_get('/cut_key'), qr!^HTTP/1\.1 502 !,
	'Exception key cut inside a char');

# Exception key and detailMessage announcing more chars than are present: the
# decoder fails on a string owned by its caller, which it must not free
like(http_get('/short_key'), qr!^HTTP/1\.1 502 !, 'Exception key too short');
like(http_get('/short_detail'), qr!^HTTP/1\.1 502 !,
	'Exception detailMessage too short');

like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed response after the failures');

$t->stop();

my $log = $t->read_file('error.log');

my @cut = $log =~ /parse exception failed .*truncated utf-8 sequence/g;
is(scalar @cut, 2, 'cut chars rejected where the payload ends');

my @short = $log =~ /parse exception failed .*parse_utf8_string\(\): will/g;
is(scalar @short, 2, 'short strings rejected up front');

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

		# { "body": b"hello", "status": "200" }
		m_ok => $flag . 'H'
			. "\x04" . 'body' . "B\x00\x05" . 'hello'
			. "\x06" . 'status' . "\x03" . '200'
			. 'Z',

		# { "status": "200", "x": ... } with the payload ending right
		# after the 3-byte lead of the second char of "x"
		m_cut_value => $flag . 'H'
			. "\x06" . 'status' . "\x03" . '200'
			. "\x01" . 'x' . "\x02" . 'A' . "\xe0",

		# an Exception whose first key is cut the same way
		m_cut_key => $flag . 'M'
			. "\x13" . 'java.lang.Exception'
			. "S\x00\x02" . 'a' . "\xe4",

		# an Exception whose first key announces 5 chars and carries 1
		m_short_key => $flag . 'M'
			. "\x13" . 'java.lang.Exception'
			. "S\x00\x05" . 'a',

		# an Exception whose detailMessage announces 5 chars, carries 1
		m_short_detail => $flag . 'M'
			. "\x13" . 'java.lang.Exception'
			. "S\x00\x0d" . 'detailMessage'
			. "S\x00\x05" . 'a',
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
					/(m_(?:ok|cut_value|cut_key|short_key|short_detail))/;
				next unless defined $method;

				my $reply = $replies{$method};

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02, 20, $id,
					length($reply)) . $reply);
			}
		}
	}
}

###############################################################################
