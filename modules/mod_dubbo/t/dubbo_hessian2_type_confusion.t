#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for the type-confusion guard in ngx_dubbo_hessian2_decode_payload_map().
#
# The decoder used to cast the Object* returned by read_object() straight to
# Map*, without checking the real dynamic type.  A backend that replies with a
# non-map Hessian2 object (Boolean, String, Integer, Long, Date, ByteArray, ...)
# therefore made the worker read the std::map member out of a much smaller
# allocation: an out-of-bounds read under a sanitizer, a SIGSEGV in an ordinary
# build.
#
# Each case below sends one of the exact payloads from the report and expects a
# 502, with the worker left running.  A well-formed map response must still
# decode to a 200.

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
	->has(qw/http mod_dubbo ngx_multi_upstream_module/)->plan(15)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    # One upstream per case, so that every case gets a connection of its own
    # and the decoder works on a payload buffer sized for that response alone.

    upstream u_ok {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_boolean {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_long {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_date {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_string {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_byte_array {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_integer {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_double {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_null {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_non_string_key {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_body_not_bytes {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    server {
        listen       127.0.0.1:%%PORT_8080%%;
        server_name  localhost;

        location /ok {
            dubbo_pass test.Service 1.0.0 m_ok u_ok;
        }

        location /boolean {
            dubbo_pass test.Service 1.0.0 m_boolean u_boolean;
        }

        location /long {
            dubbo_pass test.Service 1.0.0 m_long u_long;
        }

        location /date {
            dubbo_pass test.Service 1.0.0 m_date u_date;
        }

        location /string {
            dubbo_pass test.Service 1.0.0 m_string u_string;
        }

        location /byte_array {
            dubbo_pass test.Service 1.0.0 m_byte_array u_byte_array;
        }

        location /integer {
            dubbo_pass test.Service 1.0.0 m_integer u_integer;
        }

        location /double {
            dubbo_pass test.Service 1.0.0 m_double u_double;
        }

        location /null {
            dubbo_pass test.Service 1.0.0 m_null u_null;
        }

        location /non_string_key {
            dubbo_pass test.Service 1.0.0 m_non_string_key u_non_string_key;
        }

        location /body_not_bytes {
            dubbo_pass test.Service 1.0.0 m_body_not_bytes u_body_not_bytes;
        }
    }
}

EOF

$t->run_daemon(\&dubbo_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# A well-formed map response still decodes to a 200.
like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed map response');

# Each non-map payload from the report must be rejected with a 502, not crash
# the worker.  These are the exact byte sequences from section 4 of the report.

# 0x90 (int 0) then 0x46 0x00 = Boolean false -- the 3-byte reproducer
like(http_get('/boolean'), qr!^HTTP/1\.1 502 !,
	'Boolean payload rejected');

# 0x90 then 0x38 + 8 bytes = Long
like(http_get('/long'), qr!^HTTP/1\.1 502 !,
	'Long payload rejected');

# 0x90 then 0x4a + 8 bytes = Date
like(http_get('/date'), qr!^HTTP/1\.1 502 !,
	'Date payload rejected');

# 0x90 then 0x01 'a' = one-char String
like(http_get('/string'), qr!^HTTP/1\.1 502 !,
	'String payload rejected');

# 0x90 then 0x22 '0' '0' '0' = three-byte ByteArray
like(http_get('/byte_array'), qr!^HTTP/1\.1 502 !,
	'ByteArray payload rejected');

# 0x90 then 'I' + 4 bytes = Integer
like(http_get('/integer'), qr!^HTTP/1\.1 502 !,
	'Integer payload rejected');

# 0x90 then 'D' + 8 bytes = Double
like(http_get('/double'), qr!^HTTP/1\.1 502 !,
	'Double payload rejected');

# 0x90 then 'N' = null object
like(http_get('/null'), qr!^HTTP/1\.1 502 !,
	'null payload rejected');

# A map whose key is an Integer rather than a String: the entry is skipped,
# the remaining entries still decode.  The "status" entry carries the 200;
# without it the response handler would default to a 502.
like(http_get('/non_string_key'), qr!^HTTP/1\.1 200 !,
	'map with non-string key skipped');

# A map whose "body" value is a String rather than a ByteArray: the generic
# Object::to_string() path handles it, so the response still decodes.
like(http_get('/body_not_bytes'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'body value that is not a ByteArray still decodes');

# The worker must survive every case above.
like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed response after all the failures');

$t->stop();

my $log = $t->read_file('error.log');

# Every non-map payload must have been logged with the new diagnostic.
my @type_errors = $log =~ /parse result map failed, unexpected object type/g;
is(scalar @type_errors, 8, 'each non-map payload logged a type error');

# The non-string key case must have been logged as a skipped entry.
my @key_warnings = $log =~ /skipping map entry with non-string key/g;
is(scalar @key_warnings, 1, 'non-string key logged as skipped');

unlike($log, qr/exited on signal/, 'no worker crashed');

###############################################################################

# A Dubbo provider that answers every request with the payload chosen by the
# method name found in it, under the request id it came with.

sub dubbo_daemon {
	my ($port) = @_;

	# hessian2 response payloads: the RESPONSE_VALUE flag as an int, then
	# the value.  0x90 is the compact encoding of int 0.
	my $flag = "\x90";

	my %replies = (

		# { "body": b"hello", "status": "200" } -- a correct map
		m_ok => $flag . 'H'
			. "\x04" . 'body' . "B\x00\x05" . 'hello'
			. "\x06" . 'status' . "\x03" . '200'
			. 'Z',

		# Boolean false (0x46 0x00) -- the 3-byte reproducer
		m_boolean => $flag . "\x46\x00",

		# Long (0x38 + 8 bytes)
		m_long => $flag . "\x38" . "\x00\x00\x00\x00\x00\x00\x00\x00",

		# Date (0x4a + 8 bytes)
		m_date => $flag . "\x4a" . "\x00\x00\x00\x00\x00\x00\x00\x00",

		# one-char String (0x01 'a')
		m_string => $flag . "\x01" . 'a',

		# three-byte ByteArray (0x22 '0' '0' '0')
		m_byte_array => $flag . "\x22" . '000',

		# Integer ('I' + 4 bytes)
		m_integer => $flag . 'I' . "\x00\x00\x00\x01",

		# Double ('D' + 8 bytes)
		m_double => $flag . 'D' . "\x00\x00\x00\x00\x00\x00\x00\x00",

		# null object ('N')
		m_null => $flag . 'N',

		# a map whose first key is an Integer (0x91 = int 1), not a
		# String: that entry is skipped, the "status" entry survives
		m_non_string_key => $flag . 'H'
			. "\x91"
			. "\x03" . '200'
			. "\x06" . 'status' . "\x03" . '200'
			. 'Z',

		# a map whose "body" value is a String rather than a ByteArray:
		# the generic Object::to_string() path still decodes it
		m_body_not_bytes => $flag . 'H'
			. "\x04" . 'body' . "\x05" . 'hello'
			. "\x06" . 'status' . "\x03" . '200'
			. 'Z',
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
					/(m_(?:ok|boolean|long|date|string|byte_array|integer|double|null|non_string_key|body_not_bytes))/;
				next unless defined $method;

				my $reply = $replies{$method};

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02, 20, $id,
					length($reply)) . $reply);
			}
		}
	}
}

###############################################################################
