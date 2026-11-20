#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for dubbo_pass decoding a hessian2 map whose type is the null tag 'N'.
#
# read_map() reads the type of a typed map ('M') with read_utf8_string(), and
# that returns NULL for 'N' -- so a backend answering with "MN" used to make
# the worker dereference a NULL std::string and die on a SEGV. The type is now
# rejected instead: each such response must end in a 502, with the worker left
# running. A type that is present but empty ("M\x00") is legal and must keep
# decoding, so the guard is not allowed to reject it along with the null one.

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
	->has(qw/http mod_dubbo ngx_multi_upstream_module/)->plan(8)
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

    upstream u_null_type {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_nested_value {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_nested_key {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_empty_type {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_typed {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    upstream u_ok {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    server {
        listen       127.0.0.1:%%PORT_8080%%;
        server_name  localhost;

        location /null_type {
            dubbo_pass test.Service 1.0.0 m_null_type u_null_type;
        }

        location /nested_value {
            dubbo_pass test.Service 1.0.0 m_nested_value u_nested_value;
        }

        location /nested_key {
            dubbo_pass test.Service 1.0.0 m_nested_key u_nested_key;
        }

        location /empty_type {
            dubbo_pass test.Service 1.0.0 m_empty_type u_empty_type;
        }

        location /typed {
            dubbo_pass test.Service 1.0.0 m_typed u_typed;
        }

        location /ok {
            dubbo_pass test.Service 1.0.0 m_ok u_ok;
        }
    }
}

EOF

$t->run_daemon(\&dubbo_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

# the whole result is a typed map whose type is the null tag
like(http_get('/null_type'), qr!^HTTP/1\.1 502 !, 'null map type');

# the same map nested in an untyped one, as its value: the path of the report,
# read_object() -> read_map() -> read_object() -> read_map()
like(http_get('/nested_value'), qr!^HTTP/1\.1 502 !,
	'null map type nested as a value');

# and as its key, so the null type is reached on the first read_object()
like(http_get('/nested_key'), qr!^HTTP/1\.1 502 !,
	'null map type nested as a key');

# a type that is present but empty is legal: it falls back to the default
# classname and must not be rejected along with the null one
like(http_get('/empty_type'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'empty map type still decodes');

# as does a typed map carrying a real type
like(http_get('/typed'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'typed map still decodes');

# the worker survived all three and keeps serving
like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed response after the failures');

$t->stop();

my $log = $t->read_file('error.log');

my @null = $log =~ /parse exception failed .*null map type/g;
is(scalar @null, 3, 'null map type rejected once per request');

unlike($log, qr/exited on signal/, 'no worker crashed');

###############################################################################

# A Dubbo provider that answers every request with the payload chosen by the
# method name found in it, under the request id it came with.

sub dubbo_daemon {
	my ($port) = @_;

	# hessian2 response payloads: the RESPONSE_VALUE flag as an int, then
	# the value
	my $flag = "I\x00\x00\x00\x01";

	# the entries of a result map the module turns into a 200
	my $entries = "\x04" . 'body' . "B\x00\x05" . 'hello'
		. "\x06" . 'status' . "\x03" . '200';

	my %replies = (

		# { "body": b"hello", "status": "200" }
		m_ok => $flag . 'H' . $entries . 'Z',

		# the same, as a typed map: 'M' with a type of 0 chars
		m_empty_type => $flag . 'M' . "\x00" . $entries . 'Z',

		# and with a type that is there
		m_typed => $flag . 'M' . "\x09" . 'test.Type'
			. $entries . 'Z',

		# 'M' announcing a type, then the null tag where the type
		# should be: read_utf8_string() hands back NULL for it
		m_null_type => $flag . 'M' . 'N',

		# that map as the value of an entry of an untyped map
		m_nested_value => $flag . 'H' . "\x01" . 'k' . 'M' . 'N',

		# and as its key
		m_nested_key => $flag . 'H' . 'M' . 'N',
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
					/(m_(?:null_type|nested_value|nested_key|empty_type|typed|ok))/;
				next unless defined $method;

				my $reply = $replies{$method};

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02, 20, $id,
					length($reply)) . $reply);
			}
		}
	}
}

###############################################################################
