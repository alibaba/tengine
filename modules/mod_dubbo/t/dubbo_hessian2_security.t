#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Security tests for the mod_dubbo hessian2 codec, on both directions:
#
#  - request side: dubbo_pass_set hands request-derived values ($arg_x) to
#    the encoder. A value ending in an incomplete multi-byte UTF-8 sequence
#    (e.g. %C3) used to make write_utf8_string() read past the value buffer
#    and carry the over-read bytes into the Dubbo request. The backend here
#    checks the encoded bytes it actually receives, so the cases fail even
#    without a sanitizer build; under ASan the over-read itself is reported.
#
#  - response side: a payload of repeated map-start tags used to recurse
#    read_object()/read_map() until the stack was exhausted, killing the
#    worker. The nesting limit must turn it into a 502 with the worker
#    still serving afterwards.

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

    upstream u_enc {
        multi 1;
        server 127.0.0.1:%%PORT_8081%%;
    }

    # its own upstream, so the deep response gets a buffer of its own
    upstream u_deep {
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

        location /enc_ok {
            dubbo_pass_set args $arg_x;
            dubbo_pass test.Service 1.0.0 m_enc_ok u_enc;
        }

        location /enc_cut2 {
            dubbo_pass_set args $arg_x;
            dubbo_pass test.Service 1.0.0 m_enc_cut2 u_enc;
        }

        location /enc_cut3 {
            dubbo_pass_set args $arg_x;
            dubbo_pass test.Service 1.0.0 m_enc_cut3 u_enc;
        }

        location /enc_empty {
            dubbo_pass_set args $arg_x;
            dubbo_pass test.Service 1.0.0 m_enc_empty u_enc;
        }

        location /deep {
            dubbo_pass test.Service 1.0.0 m_deep u_deep;
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

# a complete 2-byte char in the argument keeps its encoding
like(http_get('/enc_ok?x=hello%C3%A9'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0aok$!s,
	'well-formed multi-byte argument');

# the value ends in a 2-byte lead: only the complete chars may be encoded
like(http_get('/enc_cut2?x=AAAA%C3'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0aok$!s,
	'argument cut inside a 2-byte char');

# the value ends inside a 3-byte char
like(http_get('/enc_cut3?x=AAAA%E4%B8'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0aok$!s,
	'argument cut inside a 3-byte char');

# the whole value is one incomplete sequence: an empty string, no over-read
like(http_get('/enc_empty?x=%C3'),
	qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0aok$!s,
	'argument made of a lone lead byte');

# 100000 nested map tags: the nesting limit must reject the payload
like(http_get('/deep'), qr!^HTTP/1\.1 502 !, 'deeply nested response');

# the worker survived and keeps serving
like(http_get('/ok'), qr!^HTTP/1\.1 200 .*\x0d\x0a\x0d\x0ahello$!s,
	'well-formed response after the attack');

$t->stop();

my $log = $t->read_file('error.log');

my @deep = $log =~ /parse exception failed .*maximum nesting depth exceeded/g;
is(scalar @deep, 1, 'deep payload rejected by the nesting limit');

unlike($log, qr/exited on signal/, 'no worker crashed');

###############################################################################

# A Dubbo provider that answers every request with the payload chosen by the
# method name found in it, under the request id it came with. For the m_enc_*
# methods it first checks the encoded "args" value in the request and answers
# "ok" only when the encoder produced exactly the expected bytes.

sub dubbo_daemon {
	my ($port) = @_;

	# hessian2 response payloads: the RESPONSE_VALUE flag as an int, then
	# the value
	my $flag = "I\x00\x00\x00\x01";

	my $map_ok = $flag . 'H'
		. "\x04" . 'body' . "B\x00\x05" . 'hello'
		. "\x06" . 'status' . "\x03" . '200'
		. 'Z';

	my $map_body_ok = $flag . 'H'
		. "\x04" . 'body' . "B\x00\x02" . 'ok'
		. "\x06" . 'status' . "\x03" . '200'
		. 'Z';

	# the encoded "args" entry each m_enc_* request must carry:
	# key "args" (4 chars), then the value with its char count
	my %expect = (
		m_enc_ok    => "\x04" . 'args' . "\x06" . 'hello' . "\xc3\xa9",
		m_enc_cut2  => "\x04" . 'args' . "\x04" . 'AAAA',
		m_enc_cut3  => "\x04" . 'args' . "\x04" . 'AAAA',
		m_enc_empty => "\x04" . 'args' . "\x00",
	);

	my %replies = (
		m_ok   => $map_ok,

		# 100000 map-start tags: no closing 'Z' is needed to drive the
		# old decoder into a stack overflow
		m_deep => $flag . ('H' x 100000) . 'Z',
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
					/(m_(?:enc_ok|enc_cut2|enc_cut3|enc_empty|deep|ok))/;
				next unless defined $method;

				my $reply;

				if (exists $expect{$method}) {
					$reply = index($payload, $expect{$method}) >= 0
						? $map_body_ok
						: $flag . 'H'
							. "\x04" . 'body' . "B\x00\x03" . 'bad'
							. "\x06" . 'status' . "\x03" . '200'
							. 'Z';
				} else {
					$reply = $replies{$method};
				}

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02, 20, $id,
					length($reply)) . $reply);
			}
		}
	}
}

###############################################################################
