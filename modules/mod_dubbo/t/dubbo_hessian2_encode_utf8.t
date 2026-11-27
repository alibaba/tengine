#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for the hessian2 encoder of dubbo_pass: a request value whose last
# char is an incomplete multi-byte UTF-8 sequence must not make the encoder
# read past the value it was given. The provider below echoes back every
# value it decodes, byte count and bytes, so an over-read shows up as extra
# bytes in the response body -- and, on a sanitizer build, as a report that
# fails the case on its own.
#
# The values are long enough to sit on the heap rather than inside the string
# object that carries them, which is what makes the over-read a read past an
# allocation.

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
	->has(qw/http mod_dubbo ngx_multi_upstream_module/)->plan(13)
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

    server {
        listen       127.0.0.1:%%PORT_8080%%;
        server_name  localhost;

        # the encoded value is the request URI, unescaped by nginx: a "%E0"
        # at the end of it is a 3-byte lead with nothing after it.
        # dubbo_pass_all_headers is on by default, which would put every
        # request header into the argument map next to the value under test
        location /enc {
            dubbo_pass_all_headers off;
            dubbo_pass_set uri $uri;
            dubbo_pass test.Service 1.0.0 m_enc u_enc;
        }

        # the encoded value is a header, so the incomplete sequence can be
        # placed in the middle of it as well
        location /mid {
            dubbo_pass_all_headers off;
            dubbo_pass_set mid $http_x_mid;
            dubbo_pass test.Service 1.0.0 m_mid u_enc;
        }
    }
}

EOF

$t->run_daemon(\&dubbo_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $prefix = '/enc/';

# request URI as sent, and the value the provider must see for it
my @cases = (
	[ 'plain ascii', $prefix . 'a' x 20, $prefix . 'a' x 20 ],

	# a lead byte with no continuation bytes left: the char is incomplete,
	# so it carries no data and must not drag the bytes behind it along
	[ '2-byte lead cut', $prefix . 'a' x 19 . '%C3', $prefix . 'a' x 19 ],
	[ '3-byte lead cut', $prefix . 'a' x 19 . '%E0', $prefix . 'a' x 19 ],
	[ '4-byte lead cut', $prefix . 'a' x 19 . '%F0', $prefix . 'a' x 19 ],

	# a complete multi-byte char at the very end must survive: the fix is
	# about incomplete sequences only
	[ 'complete 2-byte char', $prefix . 'a' x 18 . '%C3%A9',
		$prefix . 'a' x 18 . "\xc3\xa9" ],
);

foreach my $case (@cases) {
	my ($name, $uri, $want) = @$case;

	my $r = http_get($uri);

	like($r, qr!^HTTP/1\.1 200 !, "$name: response");
	is(body_of($r), echo_of(uri => $want), "$name: encoded value");
}

# an incomplete sequence in the middle of a value is data like any other: it
# is counted as one char and passed on, since the buffer does not end there
my $mid = 'aaa' . "\xe0" . 'bbb';

my $r = http(<<EOF);
GET /mid HTTP/1.0
Host: localhost
X-Mid: $mid

EOF

like($r, qr!^HTTP/1\.1 200 !, 'stray lead byte mid-value: response');
is(body_of($r), echo_of(mid => $mid), 'stray lead byte mid-value: encoded');

$t->stop();

unlike($t->read_file('error.log'), qr/exited on signal/, 'no worker crashed');

###############################################################################

# what the provider echoes for a single map entry: its byte count and its
# bytes in hex, so neither an over-read nor a dropped tail can go unnoticed
# and no binary data has to travel back through the response

sub echo_of {
	my ($key, $value) = @_;

	return sprintf('%s=%d:%s', $key, length($value), unpack('H*', $value));
}

sub body_of {
	my ($response) = @_;

	my ($body) = $response =~ /\x0d\x0a\x0d\x0a(.*)$/s;

	return defined $body ? $body : '';
}

###############################################################################

# hessian2 string: returns the bytes and advances the position past them. The
# length a hessian2 string carries is a char count, so the bytes are walked
# one sequence at a time, with the same lead byte rules the encoder uses.

sub h2_string {
	my ($payload, $pos) = @_;

	return undef if $$pos >= length($$payload);

	my $tag = ord(substr($$payload, $$pos, 1));
	$$pos += 1;

	if ($tag == 0x4e) {				# 'N'
		return undef;
	}

	my $chars;

	if ($tag <= 0x1f) {
		$chars = $tag;

	} elsif ($tag >= 0x30 && $tag <= 0x33) {
		$chars = (($tag - 0x30) << 8)
			+ ord(substr($$payload, $$pos, 1));
		$$pos += 1;

	} elsif ($tag == 0x53) {			# 'S'
		$chars = unpack('n', substr($$payload, $$pos, 2));
		$$pos += 2;

	} else {
		die sprintf('unexpected string tag 0x%02x', $tag);
	}

	my $start = $$pos;
	my $end = length($$payload);

	for (my $i = 0; $i < $chars && $$pos < $end; $i++) {
		my $b = ord(substr($$payload, $$pos, 1));
		my $seq = 1;

		if ($b & 0x80) {
			if (($b & 0xe0) == 0xc0) {
				$seq = 2;
			} elsif (($b & 0xf0) == 0xe0) {
				$seq = 3;
			} else {
				$seq = 4;
			}
		}

		$seq = $end - $$pos if $$pos + $seq > $end;

		$$pos += $seq;
	}

	return substr($$payload, $start, $$pos - $start);
}

sub h2_string_encode {
	my ($value) = @_;

	my $n = length($value);

	return chr($n) . $value if $n <= 0x1f;
	return chr(0x30 + ($n >> 8)) . chr($n & 0xff) . $value if $n <= 0x3ff;

	return 'S' . pack('n', $n) . $value;
}

# hessian2 untyped map: 'H' (key value)* 'Z'. The module only ever puts
# strings into the request map, so values are read as strings too.

sub h2_map {
	my ($payload, $pos) = @_;

	my $tag = substr($$payload, $$pos, 1);
	$$pos += 1;

	die sprintf('expected a map, got 0x%02x', ord($tag)) unless $tag eq 'H';

	my %map;

	while ($$pos < length($$payload)) {
		last if substr($$payload, $$pos, 1) eq 'Z';

		my $key = h2_string($payload, $pos);
		my $value = h2_string($payload, $pos);

		die 'map entry cut short' unless defined $key;

		$map{$key} = defined $value ? $value : '';
	}

	$$pos += 1 if $$pos < length($$payload);

	return \%map;
}

###############################################################################

# A Dubbo provider that answers every request with what its argument map
# carried, under the request id it came with.

sub dubbo_daemon {
	my ($port) = @_;

	# the RESPONSE_VALUE flag as an int32, then the result map
	my $flag = "I\x00\x00\x00\x01";

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

			# header: magic(2) flag(1) status(1) id(8) length(4)
			while (length($in{$fh}) >= 16) {
				my ($flags, $id, $len) =
					unpack('x2 C x a8 N', $in{$fh});
				last if length($in{$fh}) < 16 + $len;

				my $payload = substr($in{$fh}, 16, $len);
				substr($in{$fh}, 0, 16 + $len) = '';

				# heartbeats need no answer
				next if $flags & 0x20;

				my $body = decode_args(\$payload);

				my $reply = $flag . 'H'
					. h2_string_encode('body')
					. h2_string_encode($body)
					. h2_string_encode('status')
					. h2_string_encode('200')
					. 'Z';

				$fh->syswrite(pack('n C C a8 N', 0xdabb, 0x02,
					20, $id, length($reply)) . $reply);
			}
		}
	}
}

# request payload: dubbo version, service name, service version, method name
# and argument types, all hessian2 strings, then the single map argument

sub decode_args {
	my ($payload) = @_;

	my $echo = eval {
		my $pos = 0;

		h2_string($payload, \$pos) for (1 .. 5);

		my $map = h2_map($payload, \$pos);

		join(',', map {
			sprintf('%s=%d:%s', $_, length($map->{$_}),
				unpack('H*', $map->{$_}))
		} sort keys %$map);
	};

	return defined $echo ? $echo : "ERROR: $@";
}

###############################################################################
