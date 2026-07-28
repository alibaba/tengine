package Test::Nginx::HTTP3;

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Module for nginx QUIC tests.

###############################################################################

use warnings;
use strict;

use IO::Socket::INET;
use IO::Select;
use Data::Dumper;

use Test::Nginx;

sub new {
	my $self = {};
	bless $self, shift @_;

	my ($port, %extra) = @_;

	require Crypt::KeyDerivation;
	require Crypt::PK::ECC;
	require Crypt::PK::X25519;
	require Crypt::PRNG;
	require Crypt::AuthEnc::GCM;
	require Crypt::AuthEnc::CCM;
	require Crypt::AuthEnc::ChaCha20Poly1305;
	require Crypt::Mode::CTR;
	require Crypt::Stream::ChaCha;
	require Crypt::Digest;
	require Crypt::Mac::HMAC;

	$self->{socket} = IO::Socket::INET->new(
		Proto => "udp",
		PeerAddr => '127.0.0.1:' . port($port || 8980),
	);

	$self->{repeat} = 0;
	$self->{token} = $extra{token} || '';
	$self->{psk_list} = $extra{psk_list} || [];
	$self->{early_data} = $extra{early_data};
	$self->{send_ack} = 1;

	$self->{sni} = exists $extra{sni} ? $extra{sni} : 'localhost';
	$self->{cipher} = 0x1301;
	$self->{ciphers} = $extra{ciphers} || "\x13\x01";
	$self->{group} = $extra{group} || 'x25519';
	$self->{ccomp} = $extra{ccomp} || [];
	$self->{opts} = $extra{opts};
	$self->{chaining} = $extra{start_chain} || 0;

	$self->{zero} = pack("x5");

	$self->{static_encode} = [ static_table() ];
	$self->{static_decode} = [ static_table() ];
	$self->{dynamic_encode} = [];
	$self->{last_stream} = -4;
	$self->{buf} = '';

	$self->init();
	$self->init_key_schedule();
	$self->retry(%extra) or return;

	return $self;
}

sub init {
	my ($self) = @_;
	$self->{keys} = [];
	$self->{key_phase} = 0;
	$self->{pn} = [[-1, -1, -1, -1], [-1, -1, -1, -1]];
	$self->{crypto_in} = [[],[],[],[]];
	$self->{stream_in} = [];
	$self->{frames_in} = [];
	$self->{frames_incomplete} = [];
	$self->{tlsm} = ();
	$self->{tlsm}{$_} = ''
		for 'ch', 'sh', 'ee', 'cert', 'cv', 'sf', 'cf', 'nst';
	$self->{requests} = 0;

	# Initial

	$self->{odcid} = undef;
	$self->{scid} = Crypt::PRNG::random_bytes(17);
	$self->{dcid} = Crypt::PRNG::random_bytes(18);
	$self->{salt} = "\x38\x76\x2c\xf7\xf5\x59\x34\xb3\x4d\x17"
			.  "\x9a\xe6\xa4\xc8\x0c\xad\xcc\xbb\x7f\x0a";
	$self->{ncid} = [];
}

sub retry {
	my ($self, %extra) = @_;
	my $prk = Crypt::KeyDerivation::hkdf_extract($self->{dcid},
		$self->{salt}, 'SHA256');

	Test::Nginx::log_core('||', "scid = " . unpack("H*", $self->{scid}));
	Test::Nginx::log_core('||', "dcid = " . unpack("H*", $self->{dcid}));
	Test::Nginx::log_core('||', "prk = " . unpack("H*", $prk));

	$self->set_traffic_keys('tls13 client in', 'SHA256', 32, 0, 'w', $prk);
	$self->set_traffic_keys('tls13 server in', 'SHA256', 32, 0, 'r', $prk);

	$self->initial();
	return $self if $extra{probe};
	$self->handshake() or return;

	# RFC 9204, 4.3.1.  Set Dynamic Table Capacity

	my $buf = pack("B*", '001' . ipack(5, $extra{capacity} || 400));
	$self->{encoder_offset} = length($buf) + 1;
	$buf = "\x0a\x02" . build_int(length($buf) + 1) . "\x02" . $buf;

	# RFC 9114, 6.2.1.  Control Streams

	$buf = "\x0a\x06\x03\x00\x04\x00" . $buf;
	$self->{control_offset} = 3;

	$self->raw_write($buf);
}

sub init_key_schedule {
	my ($self) = @_;
	$self->{psk} = $self->{psk_list}[0];
	my ($hash, $hlen) = $self->{psk} && $self->{psk}{cipher} == 0x1302 ?
		('SHA384', 48) : ('SHA256', 32);
	$self->{es_prk} = Crypt::KeyDerivation::hkdf_extract(
		$self->{psk}->{secret} || pack("x$hlen"), pack("x$hlen"),
		$hash);
	Test::Nginx::log_core('||', "es = " . unpack("H*", $self->{es_prk}));

	$self->tls_generate_key();
}

sub initial {
	my ($self) = @_;
	$self->{tlsm}{ch} ||= $self->build_tls_client_hello();
	my $ch = $self->{tlsm}{ch};
	my $crypto = build_crypto($ch);
	my $padding = 1200 - length($crypto);
	$padding = 0 if $padding < 0;
	$padding = 0 if $self->{psk}{ed} && $self->{early_data};
	my $payload = $crypto . pack("x$padding");
	my $initial = $self->encrypt_aead($payload, 0);

	if ($self->{early_data} && $self->{psk}->{ed}) {
		my ($hash, $hlen) = $self->{psk}{cipher} == 0x1302 ?
			('SHA384', 48) : ('SHA256', 32);
		$self->set_traffic_keys('tls13 c e traffic', $hash, $hlen, 1,
			'w', $self->{es_prk}, Crypt::Digest::digest_data($hash,
			$self->{tlsm}{ch}));

		$payload = $self->build_new_stream($self->{early_data});
		$padding = 1200 - length($crypto) - length($payload);
		$payload .= pack("x$padding") if $padding > 0;
		$initial .= $self->encrypt_aead($payload, 1);
	}

	$self->{socket}->syswrite($initial);
}

sub handshake {
	my ($self) = @_;
	my $buf = '';

	$self->read_tls_message(\$buf, \&parse_tls_server_hello) or return;

	my $sh = $self->{tlsm}{sh};
	$self->{cipher} = unpack("n", substr($sh, 6 + 32 + 1, 2));

	my $extens_len = unpack("C*", substr($sh, 6 + 32 + 4, 2)) * 8
		+ unpack("C*", substr($sh, 6 + 32 + 5, 1));
	my $extens = substr($sh, 6 + 32 + 4 + 2, $extens_len);
	my $pub = ext_key_share($extens);
	Test::Nginx::log_core('||', "pub = " . unpack("H*", $pub));

	my $shared_secret = $self->tls_shared_secret($pub);
	Test::Nginx::log_core('||', "shared = " . unpack("H*", $shared_secret));

	# tls13_advance_key_schedule

	my ($hash, $hlen) = $self->{cipher} == 0x1302 ?
		('SHA384', 48) : ('SHA256', 32);

	my $psk = ext_pre_shared_key($extens);
	$self->{psk} = (defined $psk && $self->{psk_list}[$psk]) || undef;
	$self->{es_prk} = Crypt::KeyDerivation::hkdf_extract(
		$self->{psk}->{secret} || pack("x$hlen"), pack("x$hlen"),
		$hash);

	$self->{hs_prk} = hkdf_advance($hash, $hlen, $shared_secret,
		$self->{es_prk});
	Test::Nginx::log_core('||', "es = " . unpack("H*", $self->{es_prk}));
	Test::Nginx::log_core('||', "hs = " . unpack("H*", $self->{hs_prk}));

	# derive_secret_with_transcript

	my $digest = Crypt::Digest::digest_data($hash, $self->{tlsm}{ch}
		. $self->{tlsm}{sh});
	$self->set_traffic_keys('tls13 c hs traffic', $hash, $hlen, 2, 'w',
		$self->{hs_prk}, $digest);
	$self->set_traffic_keys('tls13 s hs traffic', $hash, $hlen, 2, 'r',
		$self->{hs_prk}, $digest);

	$self->read_tls_message(\$buf, \&parse_tls_encrypted_extensions);

	my $ee = $self->{tlsm}{ee};
	$extens_len = unpack("C*", substr($ee, 4, 1)) * 8
		+ unpack("C*", substr($ee, 5, 1));
	$extens = substr($ee, 6, $extens_len);
	$self->{tp} = ext_transport_parameters($extens);
	Test::Nginx::log_core('||', "tp = " . unpack("H*", $self->{tp}))
		if $self->{tp};

	unless (keys %{$self->{psk}}) {
		$self->read_tls_message(\$buf, \&parse_tls_certificate);
		$self->read_tls_message(\$buf, \&parse_tls_certificate_verify);
	}

	$self->read_tls_message(\$buf, \&parse_tls_finished);
	$self->{buf} = $buf;

	# tls13_advance_key_schedule(application)

	$self->{ms_prk} = hkdf_advance($hash, $hlen, pack("x$hlen"),
		$self->{hs_prk});
	Test::Nginx::log_core('||',
		"master = " . unpack("H*", $self->{ms_prk}));

	# derive_secret_with_transcript(application)

	$digest = Crypt::Digest::digest_data($hash, $self->{tlsm}{ch}
		. $self->{tlsm}{sh} . $self->{tlsm}{ee} . $self->{tlsm}{cert}
		. $self->{tlsm}{cv} . $self->{tlsm}{sf});
	$self->set_traffic_keys('tls13 c ap traffic', $hash, $hlen, 3, 'w',
		$self->{ms_prk}, $digest);
	$self->set_traffic_keys('tls13 s ap traffic', $hash, $hlen, 3, 'r',
		$self->{ms_prk}, $digest);

	# client finished

	my $finished = tls13_finished($hash, $hlen, $self->{keys}[2]{w}{prk},
		$digest);
	Test::Nginx::log_core('||', "finished = " . unpack("H*", $finished));

	$self->{tlsm}{cf} = $finished;

	$digest = Crypt::Digest::digest_data($hash, $self->{tlsm}{ch}
		. $self->{tlsm}{sh} . $self->{tlsm}{ee} . $self->{tlsm}{cert}
		. $self->{tlsm}{cv} . $self->{tlsm}{sf} . $self->{tlsm}{cf});
	$self->{rms_prk} = hkdf_expand_label("tls13 res master", $hash, $hlen,
		$self->{ms_prk}, $digest);
	Test::Nginx::log_core('||',
		"resumption = " . unpack("H*", $self->{rms_prk}));

	my $crypto = build_crypto($finished);
	$self->raw_write($crypto, 2);
}

sub DESTROY {
	my ($self) = @_;

	return unless $self->{socket};
	return unless $self->{keys}[3];
	my $frame = build_cc(0, "graceful shutdown");
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

sub ping {
	my ($self, $level, $pad) = @_;
	$level = 3 if !defined $level;
	$pad = 4 if !defined $pad;
	my $frame = "\x01" . "\x00" x ($pad - 1);
	$self->{socket}->syswrite($self->encrypt_aead($frame, $level));
}

sub reset_stream {
	my ($self, $sid, $code) = @_;
	my $final_size = $self->{streams}{$sid}{sent};
	my $frame = "\x04" . build_int($sid) . build_int($code)
		. build_int($final_size);
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

sub stop_sending {
	my ($self, $sid, $code) = @_;
	my $frame = "\x05" . build_int($sid) . build_int($code);
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

sub new_connection_id {
	my ($self, $seqno, $ret, $id, $token) = @_;
	my $frame = "\x18" . build_int($seqno) . build_int($ret)
		. pack("C", length($id)) . $id . $token;
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

sub path_challenge {
	my ($self, $data) = @_;
	my $frame = "\x1a" . $data;
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

sub path_response {
	my ($self, $data) = @_;
	my $frame = "\x1b" . $data;
	$self->{socket}->syswrite($self->encrypt_aead($frame, 3));
}

###############################################################################

# HTTP/3 routines

# 4.3.2.  Insert with Name Reference

sub insert_reference {
	my ($self, $name, $value, %extra) = @_;
	my $table = $extra{dyn}
		? $self->{dynamic_encode}
		: $self->{static_encode};
	my $huff = $extra{huff};
	my $hbit = $huff ? '1' : '0';
	my $dbit = $extra{dyn} ? '0' : '1';
	my ($index, $buf) = 0;

	++$index until $index > $#$table
		or $table->[$index][0] eq $name;
	$table = $self->{dynamic_encode};
	splice @$table, 0, 0, [ $name, $value ];

	$value = $huff ? huff($value) : $value;

	$buf = pack('B*', '1' . $dbit . ipack(6, $index));
	$buf .= pack('B*', $hbit . ipack(7, length($value))) . $value;

	my $offset = $self->{encoder_offset};
	my $length = length($buf);

	$self->{encoder_offset} += $length;
	$self->raw_write("\x0e\x02"
		. build_int($offset) . build_int($length) . $buf);
}

# 4.3.3.  Insert with Literal Name

sub insert_literal {
	my ($self, $name, $value, %extra) = @_;
	my $table = $self->{dynamic_encode};
	my $huff = $extra{huff};
	my $hbit = $huff ? '1' : '0';

	splice @$table, 0, 0, [ $name, $value ];

	$name = $huff ? huff($name) : $name;
	$value = $huff ? huff($value) : $value;

	my $buf = pack('B*', '01' . $hbit . ipack(5, length($name))) . $name;
	$buf .= pack('B*', $hbit . ipack(7, length($value))) . $value;

	my $offset = $self->{encoder_offset};
	my $length = length($buf);

	$self->{encoder_offset} += $length;
	$self->raw_write("\x0e\x02"
		. build_int($offset) . build_int($length) . $buf);
}

# 4.3.4.  Duplicate

sub duplicate {
	my ($self, $name, $value, %extra) = @_;
	my $table = $self->{dynamic_encode};
	my $index = 0;

	++$index until $index > $#$table
		or $table->[$index][0] eq $name;
	splice @$table, 0, 0, [ $table->[$index][0], $table->[$index][1] ];

	my $buf = pack('B*', '000' . ipack(5, $index));

	my $offset = $self->{encoder_offset};
	my $length = length($buf);

	$self->{encoder_offset} += $length;
	$self->raw_write("\x0e\x02"
		. build_int($offset) . build_int($length) . $buf);
}

sub max_push_id {
	my ($self, $val) = @_;
	$val = build_int($val);
	my $buf = "\x0d" . build_int(length($val)) . $val;

	my $offset = $self->{control_offset};
	my $length = length($buf);

	$self->{control_offset} += $length;
	$self->raw_write("\x0e\x06"
		. build_int($offset) . build_int($length) . $buf);
}

sub cancel_push {
	my ($self, $val) = @_;
	$val = build_int($val);
	my $buf = "\x03" . build_int(length($val)) . $val;

	my $offset = $self->{control_offset};
	my $length = length($buf);

	$self->{control_offset} += $length;
	$self->raw_write("\x0e\x06"
		. build_int($offset) . build_int($length) . $buf);
}

sub build_new_stream {
	my ($self, $uri, $stream) = @_;
	my ($input, $buf);

	$self->{headers} = '';

	my $host = $uri->{host} || 'localhost';
	my $method = $uri->{method} || 'GET';
	my $scheme = $uri->{scheme} || 'http';
	my $path = $uri->{path} || '/';
	my $headers = $uri->{headers};
	my $body = $uri->{body};

	if ($stream) {
		$self->{last_stream} = $stream;
	} else {
		$self->{last_stream} += 4;
	}

	unless ($headers) {
		$input = qpack($self, ":method", $method);
		$input .= qpack($self, ":scheme", $scheme);
		$input .= qpack($self, ":path", $path);
		$input .= qpack($self, ":authority", $host);
		$input .= qpack($self, "content-length", length($body))
			if $body;

	} else {
		$input = join '', map {
			qpack($self, $_->{name}, $_->{value},
			mode => $_->{mode}, huff => $_->{huff},
			idx => $_->{idx}, dyn => $_->{dyn})
		} @$headers if $headers;
	}

	# encoded field section prefix

	my $table = $self->{dynamic_encode};
	my $ric = $uri->{ric} ? $uri->{ric} : @$table ? @$table + 1 : 0;
	my $base = $uri->{base} || 0;
	$base = $base < 0 ? 0x80 + abs($base) - 1 : $base;
	$input = pack("CC", $ric, $base) . $input;

	# set length, attach headers, body

	$buf = pack("C", 1);
	$buf .= build_int(length($input));
	$buf .= $input;

	my $split = ref $uri->{body_split} && $uri->{body_split} || [];
	for (@$split) {
		$buf .= pack_body($self, substr($body, 0, $_, ""));
	}

	$buf .= pack_body($self, $body) if defined $body;

	$self->{streams}{$self->{last_stream}}{sent} = length($buf);
	$self->build_stream($buf, start => $uri->{body_more});
}

sub new_stream {
	my ($self, $uri, $stream) = @_;
	$self->raw_write($self->build_new_stream($uri, $stream));
	return $self->{last_stream};
}

sub h3_body {
	my ($self, $body, $sid, $extra) = @_;
	my $buf;

	my $split = ref $extra->{body_split} && $extra->{body_split} || [];
	for (@$split) {
		$buf .= pack_body($self, substr($body, 0, $_, ""));
	}

	$buf .= pack_body($self, $body) if defined $body;

	my $offset = $self->{streams}{$sid}{sent};

	$self->{streams}{$sid}{sent} += length($buf);
	$self->raw_write($self->build_stream($buf,
		start => $extra->{body_more}, sid => $sid, offset => $offset));
}

sub pack_body {
	my ($self, $body) = @_;

	my $buf .= pack("C", 0);
	$buf .= build_int(length($body));
	$buf .= $body;
}

sub h3_max_data {
	my ($self, $val, $stream) = @_;

	my $buf = defined $stream
		? "\x11" . build_int($stream) . build_int($val)
		: "\x10" . build_int($val);
	return $self->raw_write($buf);
}

my %cframe = (
	0 => { name => 'DATA', value => \&data },
	1 => { name => 'HEADERS', value => \&headers },
#	3 => { name => 'CANCEL_PUSH', value => \&cancel_push },
	4 => { name => 'SETTINGS', value => \&settings },
	5 => { name => 'PUSH_PROMISE', value => \&push_promise },
	7 => { name => 'GOAWAY', value => \&goaway },
);

sub read {
	my ($self, %extra) = @_;
	my (@got);
	my $s = $self->{socket};
	my $wait = $extra{wait};

	local $Data::Dumper::Terse = 1;

	while (1) {
		my ($frame, $length, $uni);
		my ($stream, $buf, $eof) = $self->read_stream_message($wait);

		unless (defined $stream) {
			return \@got unless scalar @{$self->{frames_in}};
			goto frames;
		}

		if (!length($buf) && $eof) {
			# emulate empty DATA frame
			$length = 0;
			$frame->{length} = $length;
			$frame->{type} = 'DATA';
			$frame->{data} = '';
			$frame->{flags} = $eof;
			$frame->{sid} = $stream;
			$frame->{uni} = $uni if defined $uni;
			goto push_me;
		}

		if (length($self->{frames_incomplete}[$stream]{buf})) {
			$buf = $self->{frames_incomplete}[$stream]{buf} . $buf;
		}

again:
		if (($stream % 4) == 3) {
			unless (defined $self->{stream_uni}{$stream}{stream}) {
				(my $len, $uni) = parse_int(substr($buf, 0));
				$self->{stream_uni}{$stream}{stream} = $uni;
				$buf = substr($buf, $len);

			} else {
				$uni = $self->{stream_uni}{$stream}{stream};
			}

			# push stream
			if ($uni == 1 && !$self->{stream_uni}{$stream}{push}) {
				$self->{stream_uni}{$stream}{push} = 1;
				($frame, $length) = push_stream($buf, $stream);
				goto push_me;
			}

			# decoder
			if ($uni == 3) {
				($frame, $length) = push_decoder($buf, $stream);
				goto push_me;
			}
		}

		my $offset = 0;
		my ($len, $type);

		($len, $type) = parse_int(substr($buf, $offset));

		if (!defined $len) {
			$self->{frames_incomplete}[$stream]{buf} = $buf;
			next;
		}

		$offset += $len;

		($len, $length) = parse_int(substr($buf, $offset));

		if (!defined $len) {
			$self->{frames_incomplete}[$stream]{buf} = $buf;
			next;
		}

		$offset += $len;

		$self->{frames_incomplete}[$stream]{type} = $type;
		$self->{frames_incomplete}[$stream]{length} = $length;
		$self->{frames_incomplete}[$stream]{offset} = $offset;

		if (length($buf) < $self->{frames_incomplete}[$stream]{length}
			+ $self->{frames_incomplete}[$stream]{offset})
		{
			$self->{frames_incomplete}[$stream]{buf} = $buf;
			next;
		}

		$type = $self->{frames_incomplete}[$stream]{type};
		$length = $self->{frames_incomplete}[$stream]{length};
		$offset = $self->{frames_incomplete}[$stream]{offset};

		$buf = substr($buf, $offset);
		$self->{frames_incomplete}[$stream]{buf} = "";

		$frame = $cframe{$type}{value}($self, $buf, $length);
		$frame->{length} = $length;
		$frame->{type} = $cframe{$type}{name};
		$frame->{flags} = $eof && length($buf) == $length;
		$frame->{sid} = $stream;
		$frame->{uni} = $uni if defined $uni;

push_me:
		push @got, $frame;

		Test::Nginx::log_core('||', $_) for split "\n", Dumper $frame;

		$buf = substr($buf, $length);

		last unless $extra{all} && test_fin($frame, $extra{all});
		goto again if length($buf) > 0;

frames:
		while ($frame = shift @{$self->{frames_in}}) {
			push @got, $frame;
			Test::Nginx::log_core('||', $_) for split "\n",
				Dumper $frame;
			return \@got unless test_fin($frame, $extra{all});
		}
	}
	return \@got;
}

sub push_stream {
	my ($buf, $stream) = @_;
	my $frame = { sid => $stream, uni => 1, type => 'PUSH header' };

	my ($len, $id) = parse_int($buf);
	$frame->{push_id} = $id;
	$frame->{length} = $len;

	return ($frame, $len);
}

sub push_decoder {
	my ($buf, $stream) = @_;
	my ($skip, $val) = 0;
	my $frame = { sid => $stream, uni => 3, type => '' };

	if ($skip < length($buf)) {
		my $bits = unpack("\@$skip B8", $buf);

		if (substr($bits, 0, 1) eq '1') {
			($val, $skip) = iunpack(7, $buf, $skip);
			$frame->{type} = 'DECODER_SA';

		} elsif (substr($bits, 0, 2) eq '01') {
			($val, $skip) = iunpack(6, $buf, $skip);
			$frame->{type} = 'DECODER_C';

		} elsif (substr($bits, 0, 2) eq '00') {
			($val, $skip) = iunpack(6, $buf, $skip);
			$frame->{type} = 'DECODER_ICI';
		}

		$frame->{val} = $val;
	}

	return ($frame, $skip);
}

sub test_fin {
	my ($frame, $all) = @_;
	my @test = @{$all};

	# wait for the specified DATA length

	for (@test) {
		if ($_->{length} && $frame->{type} eq 'DATA') {
			# check also for StreamID if needed

			if (!$_->{sid} || $_->{sid} == $frame->{sid}) {
				$_->{length} -= $frame->{length};
			}
		}
	}
	@test = grep { !(defined $_->{length} && $_->{length} == 0) } @test;

	# wait for the fin flag

	@test = grep { !(defined $_->{fin}
		&& (!defined $_->{sid} || $_->{sid} == $frame->{sid})
		&& $_->{fin} & $frame->{flags})
	} @test if defined $frame->{flags};

	# wait for the specified frame

	@test = grep { !($_->{type} && $_->{type} eq $frame->{type}) } @test;

	@{$all} = @test;
}

sub data {
	my ($self, $buf, $len) = @_;
	return { data => substr($buf, 0, $len) };
}

sub headers {
	my ($self, $buf, $len) = @_;
	my ($ric, $base);
	$self->{headers} = substr($buf, 0, $len);
	my $skip = 0;

	($ric, $skip) = iunpack(8, $buf, $skip);
	($base, $skip) = iunpack(7, $buf, $skip);

	$buf = substr($buf, $skip);
	$len -= $skip;
	{ headers => qunpack($self, $buf, $len) };
}

sub settings {
	my ($self, $buf, $length) = @_;
	my %payload;
	my ($offset, $len) = 0;

	while ($offset < $length) {
		my ($id, $val);
		($len, $id) = parse_int(substr($buf, $offset));
		$offset += $len;
		($len, $val) = parse_int(substr($buf, $offset));
		$offset += $len;
		$payload{$id} = $val;
	}
	return \%payload;
}

sub push_promise {
	my ($self, $buf, $length) = @_;
	my %payload;
	my ($offset, $len, $id) = 0;

	($len, $id) = parse_int($buf);
	$offset += $len;
	$payload{push_id} = $id;

	my ($ric, $base);
	my $skip = $offset;

	($ric, $skip) = iunpack(8, $buf, $skip);
	($base, $skip) = iunpack(7, $buf, $skip);

	$buf = substr($buf, $skip);
	$length -= $skip;
	$payload{headers} = qunpack($self, $buf, $length);
	return \%payload;
}

sub goaway {
	my ($self, $buf, $length) = @_;
	my ($len, $stream) = parse_int($buf);
	{ last_sid => $stream }
}

# RFC 7541, 5.1.  Integer Representation

sub ipack {
	my ($base, $d) = @_;
	return sprintf("%.*b", $base, $d) if $d < 2**$base - 1;

	my $o = sprintf("%${base}b", 2**$base - 1);
	$d -= 2**$base - 1;
	while ($d >= 128) {
		$o .= sprintf("%8b", $d % 128 + 128);
		$d >>= 7;
	}
	$o .= sprintf("%08b", $d);
	return $o;
}

sub iunpack {
	my ($base, $b, $s) = @_;

	my $len = unpack("\@$s B8", $b); $s++;
	my $huff = substr($len, 8 - $base - 1, 1);
	$len = '0' x (8 - $base) . substr($len, 8 - $base);
	$len = unpack("C", pack("B8", $len));

	return ($len, $s, $huff) if $len < 2**$base - 1;

	my $m = 0;
	my $d;

	do {
		$d = unpack("\@$s C", $b); $s++;
		$len += ($d & 127) * 2**$m;
		$m += $base;
	} while (($d & 128) == 128);

	return ($len, $s, $huff);
}

sub qpack {
	my ($ctx, $name, $value, %extra) = @_;
	my $mode = defined $extra{mode} ? $extra{mode} : 4;
	my $huff = $extra{huff};
	my $hbit = $huff ? '1' : '0';
	my $ibit = $extra{ni} ? '1' : '0';
	my $dbit = $extra{dyn} ? '0' : '1';
	my $table = $extra{dyn} ? $ctx->{dynamic_encode} : $ctx->{static_encode};
	my ($index, $buf) = 0;

	# 4.5.2.  Indexed Field Line

	if ($mode == 0) {
		++$index until $index > $#$table
			or $table->[$index][0] eq $name
			and $table->[$index][1] eq $value;
		$buf = pack('B*', '1' . $dbit . ipack(6, $index));
	}

	# 4.5.3.  Indexed Field Line with Post-Base Index

	if ($mode == 1) {
		$table = $ctx->{dynamic_encode};
		++$index until $index > $#$table
			or $table->[$index][0] eq $name
			and $table->[$index][1] eq $value;
		$buf = pack('B*', '0001' . ipack(4, 0));
	}

	# 4.5.4.  Literal Field Line with Name Reference

	if ($mode == 2) {
		++$index until $index > $#$table
			or $table->[$index][0] eq $name;
		$value = $huff ? huff($value) : $value;

		$buf = pack('B*', '01' . $ibit . $dbit . ipack(4, $index));
		$buf .= pack('B*', $hbit . ipack(7, length($value))) . $value;
	}

	# 4.5.5.  Literal Field Line with Post-Base Name Reference

	if ($mode == 3) {
		$table = $ctx->{dynamic_encode};
		++$index until $index > $#$table
			or $table->[$index][0] eq $name;
		$value = $huff ? huff($value) : $value;

		$buf = pack('B*', '0000' . $ibit . ipack(3, $index));
		$buf .= pack('B*', $hbit . ipack(7, length($value))) . $value;
	}

	# 4.5.6.  Literal Field Line with Literal Name

	if ($mode == 4) {
		$name = $huff ? huff($name) : $name;
		$value = $huff ? huff($value) : $value;

		$buf = pack('B*', '001' . $ibit .
			$hbit . ipack(3, length($name))) . $name;
		$buf .= pack('B*', $hbit . ipack(7, length($value))) . $value;
	}

	return $buf;
}

sub qunpack {
	my ($ctx, $data, $length) = @_;
	my $table = $ctx->{static_decode};
	my %headers;
	my $skip = 0;
	my ($index, $name, $value, $size);

	my $field = sub {
		my ($base, $b) = @_;
		my ($len, $s, $huff) = iunpack(@_);

		my $field = substr($b, $s, $len);
		$field = $huff ? dehuff($field) : $field;
		$s += $len;
		return ($field, $s);
	};

	my $add = sub {
		my ($h, $n, $v) = @_;
		return $h->{$n} = $v unless exists $h->{$n};
		$h->{$n} = [ $h->{$n} ] unless ref $h->{$n};
		push @{$h->{$n}}, $v;
	};

	while ($skip < $length) {
		my $ib = unpack("\@$skip B8", $data);

		# 4.5.2.  Indexed Field Line

		if (substr($ib, 0, 2) eq '11') {
			($index, $skip) = iunpack(6, $data, $skip);

			$add->(\%headers,
				$table->[$index][0], $table->[$index][1]);
			next;
		}

		# 4.5.4.  Literal Field Line with Name Reference

		if (substr($ib, 0, 4) eq '0101') {
			($index, $skip) = iunpack(4, $data, $skip);
			$name = $table->[$index][0];
			($value, $skip) = $field->(7, $data, $skip);

			$add->(\%headers, $name, $value);
			next;
		}

		# 4.5.6.  Literal Field Line with Literal Name

		if (substr($ib, 0, 4) eq '0010') {
			($name, $skip) = $field->(3, $data, $skip);
			($value, $skip) = $field->(7, $data, $skip);

			$add->(\%headers, $name, $value);
			next;
		}

		last;
	}

	return \%headers;
}

sub static_table {
	[ ':authority',			''				],
	[ ':path',			'/'				],
	[ 'age',			'0'				],
	[ 'content-disposition',	''				],
	[ 'content-length',		'0'				],
	[ 'cookie',			''				],
	[ 'date',			''				],
	[ 'etag',			''				],
	[ 'if-modified-since',		''				],
	[ 'if-none-match',		''				],
	[ 'last-modified',		''				],
	[ 'link',			''				],
	[ 'location',			''				],
	[ 'referer',			''				],
	[ 'set-cookie',			''				],
	[ ':method',			'CONNECT'			],
	[ ':method',			'DELETE'			],
	[ ':method',			'GET'				],
	[ ':method',			'HEAD'				],
	[ ':method',			'OPTIONS'			],
	[ ':method',			'POST'				],
	[ ':method',			'PUT'				],
	[ ':scheme',			'http'				],
	[ ':scheme',			'https'				],
	[ ':status',			'103'				],
	[ ':status',			'200'				],
	[ ':status',			'304'				],
	[ ':status',			'404'				],
	[ ':status',			'503'				],
	[ 'accept',			'*/*'				],
	[ 'accept',			'application/dns-message'	],
	[ 'accept-encoding',		'gzip, deflate, br'		],
	[ 'accept-ranges',		'bytes'				],
	[ 'access-control-allow-headers',	'cache-control'		],
	[ 'access-control-allow-headers',	'content-type'		],
	[ 'access-control-allow-origin',	'*'			],
	[ 'cache-control',		'max-age=0'			],
	[ 'cache-control',		'max-age=2592000'		],
	[ 'cache-control',		'max-age=604800'		],
	[ 'cache-control',		'no-cache'			],
	[ 'cache-control',		'no-store'			],
	[ 'cache-control',		'public, max-age=31536000'	],
	[ 'content-encoding',		'br'				],
	[ 'content-encoding',		'gzip'				],
	[ 'content-type',		'application/dns-message'	],
	[ 'content-type',		'application/javascript'	],
	[ 'content-type',		'application/json'		],
	[ 'content-type',	'application/x-www-form-urlencoded'	],
	[ 'content-type',		'image/gif'			],
	[ 'content-type',		'image/jpeg'			],
	[ 'content-type',		'image/png'			],
	[ 'content-type',		'text/css'			],
	[ 'content-type',		'text/html; charset=utf-8'	],
	[ 'content-type',		'text/plain'			],
	[ 'content-type',		'text/plain;charset=utf-8'	],
	[ 'range',			'bytes=0-'			],
	[ 'strict-transport-security',	'max-age=31536000'		],
	[ 'strict-transport-security',
				'max-age=31536000; includesubdomains'	],
	[ 'strict-transport-security',
			'max-age=31536000; includesubdomains; preload'	],
	[ 'vary',			'accept-encoding'		],
	[ 'vary',			'origin'			],
	[ 'x-content-type-options',	'nosniff'			],
	[ 'x-xss-protection',		'1; mode=block'			],
	[ ':status',			'100'				],
	[ ':status',			'204'				],
	[ ':status',			'206'				],
	[ ':status',			'302'				],
	[ ':status',			'400'				],
	[ ':status',			'403'				],
	[ ':status',			'421'				],
	[ ':status',			'425'				],
	[ ':status',			'500'				],
	[ 'accept-language',		''				],
	[ 'access-control-allow-credentials',	'FALSE'			],
	[ 'access-control-allow-credentials',	'TRUE'			],
	[ 'access-control-allow-headers',	'*'			],
	[ 'access-control-allow-methods',	'get'			],
	[ 'access-control-allow-methods',	'get, post, options'	],
	[ 'access-control-allow-methods',	'options'		],
	[ 'access-control-expose-headers',	'content-length'	],
	[ 'access-control-request-headers',	'content-type'		],
	[ 'access-control-request-method',	'get'			],
	[ 'access-control-request-method',	'post'			],
	[ 'alt-svc',			'clear'				],
	[ 'authorization',		''				],
	[ 'content-security-policy',
		"script-src 'none'; object-src 'none'; base-uri 'none'"	],
	[ 'early-data',			'1'				],
	[ 'expect-ct',			''				],
	[ 'forwarded',			''				],
	[ 'if-range',			''				],
	[ 'origin',			''				],
	[ 'purpose',			'prefetch'			],
	[ 'server',			''				],
	[ 'timing-allow-origin',	'*'				],
	[ 'upgrade-insecure-requests',	'1'				],
	[ 'user-agent',			''				],
	[ 'x-forwarded-for',		''				],
	[ 'x-frame-options',		'deny'				],
	[ 'x-frame-options',		'sameorigin'			],
}

sub huff_code { scalar {
	pack('C', 0)	=> '1111111111000',
	pack('C', 1)	=> '11111111111111111011000',
	pack('C', 2)	=> '1111111111111111111111100010',
	pack('C', 3)	=> '1111111111111111111111100011',
	pack('C', 4)	=> '1111111111111111111111100100',
	pack('C', 5)	=> '1111111111111111111111100101',
	pack('C', 6)	=> '1111111111111111111111100110',
	pack('C', 7)	=> '1111111111111111111111100111',
	pack('C', 8)	=> '1111111111111111111111101000',
	pack('C', 9)	=> '111111111111111111101010',
	pack('C', 10)	=> '111111111111111111111111111100',
	pack('C', 11)	=> '1111111111111111111111101001',
	pack('C', 12)	=> '1111111111111111111111101010',
	pack('C', 13)	=> '111111111111111111111111111101',
	pack('C', 14)	=> '1111111111111111111111101011',
	pack('C', 15)	=> '1111111111111111111111101100',
	pack('C', 16)	=> '1111111111111111111111101101',
	pack('C', 17)	=> '1111111111111111111111101110',
	pack('C', 18)	=> '1111111111111111111111101111',
	pack('C', 19)	=> '1111111111111111111111110000',
	pack('C', 20)	=> '1111111111111111111111110001',
	pack('C', 21)	=> '1111111111111111111111110010',
	pack('C', 22)	=> '111111111111111111111111111110',
	pack('C', 23)	=> '1111111111111111111111110011',
	pack('C', 24)	=> '1111111111111111111111110100',
	pack('C', 25)	=> '1111111111111111111111110101',
	pack('C', 26)	=> '1111111111111111111111110110',
	pack('C', 27)	=> '1111111111111111111111110111',
	pack('C', 28)	=> '1111111111111111111111111000',
	pack('C', 29)	=> '1111111111111111111111111001',
	pack('C', 30)	=> '1111111111111111111111111010',
	pack('C', 31)	=> '1111111111111111111111111011',
	pack('C', 32)	=> '010100',
	pack('C', 33)	=> '1111111000',
	pack('C', 34)	=> '1111111001',
	pack('C', 35)	=> '111111111010',
	pack('C', 36)	=> '1111111111001',
	pack('C', 37)	=> '010101',
	pack('C', 38)	=> '11111000',
	pack('C', 39)	=> '11111111010',
	pack('C', 40)	=> '1111111010',
	pack('C', 41)	=> '1111111011',
	pack('C', 42)	=> '11111001',
	pack('C', 43)	=> '11111111011',
	pack('C', 44)	=> '11111010',
	pack('C', 45)	=> '010110',
	pack('C', 46)	=> '010111',
	pack('C', 47)	=> '011000',
	pack('C', 48)	=> '00000',
	pack('C', 49)	=> '00001',
	pack('C', 50)	=> '00010',
	pack('C', 51)	=> '011001',
	pack('C', 52)	=> '011010',
	pack('C', 53)	=> '011011',
	pack('C', 54)	=> '011100',
	pack('C', 55)	=> '011101',
	pack('C', 56)	=> '011110',
	pack('C', 57)	=> '011111',
	pack('C', 58)	=> '1011100',
	pack('C', 59)	=> '11111011',
	pack('C', 60)	=> '111111111111100',
	pack('C', 61)	=> '100000',
	pack('C', 62)	=> '111111111011',
	pack('C', 63)	=> '1111111100',
	pack('C', 64)	=> '1111111111010',
	pack('C', 65)	=> '100001',
	pack('C', 66)	=> '1011101',
	pack('C', 67)	=> '1011110',
	pack('C', 68)	=> '1011111',
	pack('C', 69)	=> '1100000',
	pack('C', 70)	=> '1100001',
	pack('C', 71)	=> '1100010',
	pack('C', 72)	=> '1100011',
	pack('C', 73)	=> '1100100',
	pack('C', 74)	=> '1100101',
	pack('C', 75)	=> '1100110',
	pack('C', 76)	=> '1100111',
	pack('C', 77)	=> '1101000',
	pack('C', 78)	=> '1101001',
	pack('C', 79)	=> '1101010',
	pack('C', 80)	=> '1101011',
	pack('C', 81)	=> '1101100',
	pack('C', 82)	=> '1101101',
	pack('C', 83)	=> '1101110',
	pack('C', 84)	=> '1101111',
	pack('C', 85)	=> '1110000',
	pack('C', 86)	=> '1110001',
	pack('C', 87)	=> '1110010',
	pack('C', 88)	=> '11111100',
	pack('C', 89)	=> '1110011',
	pack('C', 90)	=> '11111101',
	pack('C', 91)	=> '1111111111011',
	pack('C', 92)	=> '1111111111111110000',
	pack('C', 93)	=> '1111111111100',
	pack('C', 94)	=> '11111111111100',
	pack('C', 95)	=> '100010',
	pack('C', 96)	=> '111111111111101',
	pack('C', 97)	=> '00011',
	pack('C', 98)	=> '100011',
	pack('C', 99)	=> '00100',
	pack('C', 100)	=> '100100',
	pack('C', 101)	=> '00101',
	pack('C', 102)	=> '100101',
	pack('C', 103)	=> '100110',
	pack('C', 104)	=> '100111',
	pack('C', 105)	=> '00110',
	pack('C', 106)	=> '1110100',
	pack('C', 107)	=> '1110101',
	pack('C', 108)	=> '101000',
	pack('C', 109)	=> '101001',
	pack('C', 110)	=> '101010',
	pack('C', 111)	=> '00111',
	pack('C', 112)	=> '101011',
	pack('C', 113)	=> '1110110',
	pack('C', 114)	=> '101100',
	pack('C', 115)	=> '01000',
	pack('C', 116)	=> '01001',
	pack('C', 117)	=> '101101',
	pack('C', 118)	=> '1110111',
	pack('C', 119)	=> '1111000',
	pack('C', 120)	=> '1111001',
	pack('C', 121)	=> '1111010',
	pack('C', 122)	=> '1111011',
	pack('C', 123)	=> '111111111111110',
	pack('C', 124)	=> '11111111100',
	pack('C', 125)	=> '11111111111101',
	pack('C', 126)	=> '1111111111101',
	pack('C', 127)	=> '1111111111111111111111111100',
	pack('C', 128)	=> '11111111111111100110',
	pack('C', 129)	=> '1111111111111111010010',
	pack('C', 130)	=> '11111111111111100111',
	pack('C', 131)	=> '11111111111111101000',
	pack('C', 132)	=> '1111111111111111010011',
	pack('C', 133)	=> '1111111111111111010100',
	pack('C', 134)	=> '1111111111111111010101',
	pack('C', 135)	=> '11111111111111111011001',
	pack('C', 136)	=> '1111111111111111010110',
	pack('C', 137)	=> '11111111111111111011010',
	pack('C', 138)	=> '11111111111111111011011',
	pack('C', 139)	=> '11111111111111111011100',
	pack('C', 140)	=> '11111111111111111011101',
	pack('C', 141)	=> '11111111111111111011110',
	pack('C', 142)	=> '111111111111111111101011',
	pack('C', 143)	=> '11111111111111111011111',
	pack('C', 144)	=> '111111111111111111101100',
	pack('C', 145)	=> '111111111111111111101101',
	pack('C', 146)	=> '1111111111111111010111',
	pack('C', 147)	=> '11111111111111111100000',
	pack('C', 148)	=> '111111111111111111101110',
	pack('C', 149)	=> '11111111111111111100001',
	pack('C', 150)	=> '11111111111111111100010',
	pack('C', 151)	=> '11111111111111111100011',
	pack('C', 152)	=> '11111111111111111100100',
	pack('C', 153)	=> '111111111111111011100',
	pack('C', 154)	=> '1111111111111111011000',
	pack('C', 155)	=> '11111111111111111100101',
	pack('C', 156)	=> '1111111111111111011001',
	pack('C', 157)	=> '11111111111111111100110',
	pack('C', 158)	=> '11111111111111111100111',
	pack('C', 159)	=> '111111111111111111101111',
	pack('C', 160)	=> '1111111111111111011010',
	pack('C', 161)	=> '111111111111111011101',
	pack('C', 162)	=> '11111111111111101001',
	pack('C', 163)	=> '1111111111111111011011',
	pack('C', 164)	=> '1111111111111111011100',
	pack('C', 165)	=> '11111111111111111101000',
	pack('C', 166)	=> '11111111111111111101001',
	pack('C', 167)	=> '111111111111111011110',
	pack('C', 168)	=> '11111111111111111101010',
	pack('C', 169)	=> '1111111111111111011101',
	pack('C', 170)	=> '1111111111111111011110',
	pack('C', 171)	=> '111111111111111111110000',
	pack('C', 172)	=> '111111111111111011111',
	pack('C', 173)	=> '1111111111111111011111',
	pack('C', 174)	=> '11111111111111111101011',
	pack('C', 175)	=> '11111111111111111101100',
	pack('C', 176)	=> '111111111111111100000',
	pack('C', 177)	=> '111111111111111100001',
	pack('C', 178)	=> '1111111111111111100000',
	pack('C', 179)	=> '111111111111111100010',
	pack('C', 180)	=> '11111111111111111101101',
	pack('C', 181)	=> '1111111111111111100001',
	pack('C', 182)	=> '11111111111111111101110',
	pack('C', 183)	=> '11111111111111111101111',
	pack('C', 184)	=> '11111111111111101010',
	pack('C', 185)	=> '1111111111111111100010',
	pack('C', 186)	=> '1111111111111111100011',
	pack('C', 187)	=> '1111111111111111100100',
	pack('C', 188)	=> '11111111111111111110000',
	pack('C', 189)	=> '1111111111111111100101',
	pack('C', 190)	=> '1111111111111111100110',
	pack('C', 191)	=> '11111111111111111110001',
	pack('C', 192)	=> '11111111111111111111100000',
	pack('C', 193)	=> '11111111111111111111100001',
	pack('C', 194)	=> '11111111111111101011',
	pack('C', 195)	=> '1111111111111110001',
	pack('C', 196)	=> '1111111111111111100111',
	pack('C', 197)	=> '11111111111111111110010',
	pack('C', 198)	=> '1111111111111111101000',
	pack('C', 199)	=> '1111111111111111111101100',
	pack('C', 200)	=> '11111111111111111111100010',
	pack('C', 201)	=> '11111111111111111111100011',
	pack('C', 202)	=> '11111111111111111111100100',
	pack('C', 203)	=> '111111111111111111111011110',
	pack('C', 204)	=> '111111111111111111111011111',
	pack('C', 205)	=> '11111111111111111111100101',
	pack('C', 206)	=> '111111111111111111110001',
	pack('C', 207)	=> '1111111111111111111101101',
	pack('C', 208)	=> '1111111111111110010',
	pack('C', 209)	=> '111111111111111100011',
	pack('C', 210)	=> '11111111111111111111100110',
	pack('C', 211)	=> '111111111111111111111100000',
	pack('C', 212)	=> '111111111111111111111100001',
	pack('C', 213)	=> '11111111111111111111100111',
	pack('C', 214)	=> '111111111111111111111100010',
	pack('C', 215)	=> '111111111111111111110010',
	pack('C', 216)	=> '111111111111111100100',
	pack('C', 217)	=> '111111111111111100101',
	pack('C', 218)	=> '11111111111111111111101000',
	pack('C', 219)	=> '11111111111111111111101001',
	pack('C', 220)	=> '1111111111111111111111111101',
	pack('C', 221)	=> '111111111111111111111100011',
	pack('C', 222)	=> '111111111111111111111100100',
	pack('C', 223)	=> '111111111111111111111100101',
	pack('C', 224)	=> '11111111111111101100',
	pack('C', 225)	=> '111111111111111111110011',
	pack('C', 226)	=> '11111111111111101101',
	pack('C', 227)	=> '111111111111111100110',
	pack('C', 228)	=> '1111111111111111101001',
	pack('C', 229)	=> '111111111111111100111',
	pack('C', 230)	=> '111111111111111101000',
	pack('C', 231)	=> '11111111111111111110011',
	pack('C', 232)	=> '1111111111111111101010',
	pack('C', 233)	=> '1111111111111111101011',
	pack('C', 234)	=> '1111111111111111111101110',
	pack('C', 235)	=> '1111111111111111111101111',
	pack('C', 236)	=> '111111111111111111110100',
	pack('C', 237)	=> '111111111111111111110101',
	pack('C', 238)	=> '11111111111111111111101010',
	pack('C', 239)	=> '11111111111111111110100',
	pack('C', 240)	=> '11111111111111111111101011',
	pack('C', 241)	=> '111111111111111111111100110',
	pack('C', 242)	=> '11111111111111111111101100',
	pack('C', 243)	=> '11111111111111111111101101',
	pack('C', 244)	=> '111111111111111111111100111',
	pack('C', 245)	=> '111111111111111111111101000',
	pack('C', 246)	=> '111111111111111111111101001',
	pack('C', 247)	=> '111111111111111111111101010',
	pack('C', 248)	=> '111111111111111111111101011',
	pack('C', 249)	=> '1111111111111111111111111110',
	pack('C', 250)	=> '111111111111111111111101100',
	pack('C', 251)	=> '111111111111111111111101101',
	pack('C', 252)	=> '111111111111111111111101110',
	pack('C', 253)	=> '111111111111111111111101111',
	pack('C', 254)	=> '111111111111111111111110000',
	pack('C', 255)	=> '11111111111111111111101110',
	'_eos'		=> '111111111111111111111111111111',
}};

sub huff {
	my ($string) = @_;
	my $code = &huff_code;

	my $ret = join '', map { $code->{$_} } (split //, $string);
	my $len = length($ret) + (8 - length($ret) % 8);
	$ret .= $code->{_eos};

	return pack("B$len", $ret);
}

sub dehuff {
	my ($string) = @_;
	my $code = &huff_code;
	my %decode = reverse %$code;

	my $ret = ''; my $c = '';
	for (split //, unpack('B*', $string)) {
		$c .= $_;
		next unless exists $decode{$c};
		last if $decode{$c} eq '_eos';

		$ret .= $decode{$c};
		$c = '';
	}

	return $ret;
}

sub raw_write {
	my ($self, $message, $level) = @_;
	$level = 3 if !defined $level;

	if ($self->{chaining}) {
		return add_chain($self, $message, $level);
	}

	$self->{socket}->syswrite($self->encrypt_aead($message, $level));
}

sub start_chain {
	my ($self) = @_;

	$self->{chaining} = 1;
}

sub add_chain {
	my ($self, $buf, $level) = @_;

	if ($self->{chained_buf}{$level}) {
		$self->{chained_buf}{$level} .= $buf;
	} else {
		$self->{chained_buf}{$level} = $buf;
	}
}

sub send_chain {
	my ($self) = @_;

	undef $self->{chaining};
	my $buf = join '', map {
		$self->encrypt_aead($self->{chained_buf}{$_}, $_)
			if defined $self->{chained_buf}{$_}
	} 0 .. 3;
	$self->{socket}->syswrite($buf) if $buf;
	undef $self->{chained_buf};
}

###############################################################################

sub parse_frames {
	my ($buf) = @_;
	my @frames;
	my $offset = 0;

	while ($offset < length($buf)) {
		my ($tlen, $type) = parse_int(substr($buf, $offset));
		$offset += $tlen;
		next if $type == 0;
		my $frame = { type => $type };

		if ($type == 1) {
			$frame->{type} = 'PING';
		}
		if ($type == 2) {
			$frame->{type} = 'ACK';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{largest} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{delay} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{count} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{first} = $val;
			$offset += $len;
		}
		if ($type == 4) {
			$frame->{type} = 'RESET_STREAM';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{sid} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{code} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{final_size} = $val;
			$offset += $len;
		}
		if ($type == 5) {
			$frame->{type} = 'STOP_SENDING';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{sid} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{code} = $val;
			$offset += $len;
		}
		if ($type == 6) {
			my ($olen, $off) = parse_int(substr($buf, $offset));
			$offset += $olen;
			my ($llen, $len) = parse_int(substr($buf, $offset));
			$offset += $llen;
			$frame->{type} = 'CRYPTO';
			$frame->{length} = $len;
			$frame->{offset} = $off;
			$frame->{payload} = substr($buf, $offset, $len);
			$offset += $len;
		}
		if ($type == 7) {
			$frame->{type} = 'NEW_TOKEN';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$offset += $len;
			$frame->{token} = substr($buf, $offset, $val);
			$offset += $val;
		}
		if (($type & 0xf8) == 0x08) {
			$frame->{type} = 'STREAM';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{id} = $val;
			$offset += $len;
			if ($type & 0x4) {
				($len, $val) = parse_int(substr($buf, $offset));
				$frame->{offset} = $val;
				$offset += $len;
			} else {
				$frame->{offset} = 0;
			}
			if ($type & 0x2) {
				($len, $val) = parse_int(substr($buf, $offset));
				$frame->{length} = $val;
				$offset += $len;
			} else {
				$frame->{length} = length($buf) - $offset;
			}
			if ($type & 0x1) {
				$frame->{fin} = 1;
			}
			$frame->{payload} =
				substr($buf, $offset, $frame->{length});
			$offset += $frame->{length};
		}
		if ($type == 18 || $type == 19) {
			$frame->{type} = 'MAX_STREAMS';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{val} = $val;
			$frame->{uni} = 1 if $type == 19;
			$offset += $len;
		}
		if ($type == 24) {
			$frame->{type} = 'NCID';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{seqno} = $val;
			$offset += $len;
			($len, $val) = parse_int(substr($buf, $offset));
			$frame->{rpt} = $val;
			$offset += $len;
			$len = unpack("C", substr($buf, $offset, 1));
			$frame->{length} = $len;
			$offset += 1;
			$frame->{cid} = substr($buf, $offset, $len);
			$offset += $len;
			$frame->{token} = substr($buf, $offset, 16);
			$offset += 16;
		}
		if ($type == 26) {
			$frame->{type} = 'PATH_CHALLENGE';
			$frame->{data} = substr($buf, $offset, 8);
			$offset += 8;
		}
		if ($type == 27) {
			$frame->{type} = 'PATH_RESPONSE';
			$frame->{data} = substr($buf, $offset, 8);
			$offset += 8;
		}
		if ($type == 28 || $type == 29) {
			$frame->{type} = 'CONNECTION_CLOSE';
			my ($len, $val) = parse_int(substr($buf, $offset));
			$frame->{error} = $val;
			$offset += $len;
			if ($type == 28) {
				($len, $val) = parse_int(substr($buf, $offset));
				$frame->{frame_type} = $val;
				$offset += $len;
			}
			($len, $val) = parse_int(substr($buf, $offset));
			$offset += $len;
			$frame->{phrase} = substr($buf, $offset, $val);
			$offset += $val;
		}
		if ($type == 30) {
			$frame->{type} = 'HANDSHAKE_DONE';
		}
		push @frames, $frame;
	}
	return \@frames;
}

sub handle_frames {
	my ($self, $frames, $level) = @_;

	my @frames = grep { $_->{type} eq 'CRYPTO' } @$frames;
	while (my $frame = shift @frames) {
		insert_crypto($self->{crypto_in}[$level], [
			$frame->{offset},
			$frame->{length},
			$frame->{payload},
		]);

		$self->parse_tls_nst() if $level == 3;
	}

	@frames = grep { $_->{type} eq 'STREAM' } @$frames;
	while (my $frame = shift @frames) {
		$self->{stream_in}[$frame->{id}] ||= { buf => [], pos => 0 };
		insert_crypto($self->{stream_in}[$frame->{id}]->{buf}, [
			$frame->{offset},
			$frame->{length},
			$frame->{payload},
			$frame->{fin},
		]);
	}

	@frames = grep { $_->{type} eq 'NCID' } @$frames;
	while (my $frame = shift @frames) {
		push @{$self->{ncid}}, $frame;
	}

	my $ack = $self->{ack}[$level];

	# stop tracking acknowledged ACK ranges

	@frames = grep { $_->{type} eq 'ACK' } @$frames;
	while (my $frame = shift @frames) {
		my $max = $frame->{largest};
		my $min = $max - $frame->{first};

		for my $num ($min .. $max) {
			for my $pn (keys %$ack) {
				delete $ack->{$pn} if $ack->{$pn} == $num;
			}
		}
	}

	my $send_ack = $self->encrypt_aead(build_ack($ack), $level);
	$self->{socket}->syswrite($send_ack) if $self->{send_ack};

	for my $pn (keys %$ack) {
		$ack->{$pn} = $self->{pn}[0][$level] if $ack->{$pn} == -1;
	}

	my ($frame) = grep { $_->{type} eq 'NEW_TOKEN' } @$frames;
	$self->{token} = $frame->{token} || '';

	push @{$self->{frames_in}}, grep { $_->{type} ne 'CRYPTO'
		&& $_->{type} ne 'STREAM' } @$frames;
}

sub insert_crypto {
	my ($crypto, $frame) = @_;
	my $i;

	for ($i = 0; $i < scalar @$crypto; $i++) {
		# frame][crypto][frame
		my $this = @$crypto[$i];
		if (@$frame[0] <= @$this[0] &&
			@$frame[0] + @$frame[1] >= @$this[0] + @$this[1])
		{
			my $old = substr(@$frame[2], @$this[0] - @$frame[0],
				@$this[1]);
			die "bad inner" if $old ne @$this[2];
			splice @$crypto, $i, 1; $i--;
		}
	}

	return push @$crypto, $frame if !@$crypto;

	for ($i = 0; $i < @$crypto; $i++) {
		if (@$frame[0] <= @{@$crypto[$i]}[0] + @{@$crypto[$i]}[1]) {
			last;
		}
	}

	return push @$crypto, $frame if $i == @$crypto;

	my $this = @$crypto[$i];
	my $next = @$crypto[$i + 1];

	if (@$frame[0] + @$frame[1] == @$this[0]) {
		# frame][crypto
		@$this[0] = @$frame[0];
		@$this[1] += @$frame[1];
		@$this[2] = @$frame[2] . @$this[2];

	} elsif (@$this[0] + @$this[1] == @$frame[0]) {
		# crypto][frame
		@$this[1] += @$frame[1];
		@$this[2] .= @$frame[2];
		@$this[3] = @$frame[3];

	} elsif (@$frame[0] + @$frame[1] < @$this[0]) {
		# frame..crypto
		return splice @$crypto, $i, 0, $frame;

	} else {
		# overlay
		my ($b1, $b2) = @$this[0] < @$frame[0]
			? ($this, $frame) : ($frame, $this);
		my ($o1, $o2) = @$this[0] + @$this[1] < @$frame[0] + @$frame[1]
			? ($this, $frame) : ($frame, $this);
		my $offset = @$b2[0] - @$b1[0];
		my $length = @$o1[0] + @$o1[1] - @$b2[0];
		my $old = substr @$b1[2], $offset, $length, @$b2[2];
		die "bad repl" if substr(@$b1[2], $offset, $length) ne $old;
		@$this = (@$b1[0], @$o2[0] + @$o2[1] - @$b1[0], @$b1[2]);
	}

	return if !defined $next;

	# combine with next overlay if any
	if (@$this[0] + @$this[1] >= @$next[0]) {
		my $offset = @$next[0] - @$this[0];
		my $length = @$this[0] + @$this[1] - @$next[0];
		my $old = substr @$this[2], $offset, $length, @$next[2];
		die "bad repl2" if substr(@$this[2], $offset, $length) ne $old;
		@$this[1] = @$next[0] + @$next[1] - @$this[0];
		splice @$crypto, $i + 1, 1;
	}
}

###############################################################################

sub save_session_tickets {
	my ($self, $content) = @_;

	my ($hash, $hlen) = $self->{cipher} == 0x1302 ?
		('SHA384', 48) : ('SHA256', 32);

	my $nst_len = unpack("n", substr($content, 2, 2));
	my $nst = substr($content, 4, $nst_len);

	my $psk = { cipher => $self->{cipher} };
	my $lifetime = substr($nst, 0, 4);
	$psk->{age_add} = substr($nst, 4, 4);
	my $nonce_len = unpack("C", substr($nst, 8, 1));
	my $nonce = substr($nst, 9, $nonce_len);
	my $len = unpack("n", substr($nst, 8 + 1 + $nonce_len, 2));
	$psk->{ticket} = substr($nst, 11 + $nonce_len, $len);

	my $extens_len = unpack("n", substr($nst, 11 + $nonce_len + $len, 2));
	my $extens = substr($nst, 11 + $nonce_len + $len + 2, $extens_len);

	$psk->{ed} = ext_early_data($extens);
	$psk->{secret} = hkdf_expand_label("tls13 resumption", $hash, $hlen,
		$self->{rms_prk}, $nonce);
	push @{$self->{psk_list}}, $psk;
}

sub decode_pn {
	my ($self, $pn, $pnl, $level) = @_;
	my $expected = $self->{pn}[1][$level] + 1;
	my $pn_win = 1 << $pnl * 8;
	my $pn_hwin = $pn_win / 2;

	$pn |= $expected & ~($pn_win - 1);

	if ($pn <= $expected - $pn_hwin && $pn < (1 << 62) - $pn_win) {
		$pn += $pn_win;

	} elsif ($pn > $expected + $pn_hwin && $pn >= $pn_win) {
		$pn -= $pn_win;
	}

	return $pn;
}

sub decrypt_aead_f {
	my ($level, $cipher) = @_;
	if ($level == 0 || $cipher == 0x1301 || $cipher == 0x1302) {
		return \&Crypt::AuthEnc::GCM::gcm_decrypt_verify, 'AES';
	}
	if ($cipher == 0x1304) {
		return \&Crypt::AuthEnc::CCM::ccm_decrypt_verify, 'AES';
	}
	\&Crypt::AuthEnc::ChaCha20Poly1305::chacha20poly1305_decrypt_verify;
}

sub decrypt_aead {
	my ($self, $buf) = @_;
	my $flags = unpack("C", substr($buf, 0, 1));
	return 0, $self->decrypt_retry($buf) if ($flags & 0xf0) == 0xf0;
	my $level = $flags & 0x80 ? $flags - 0xc0 >> 4 : 3;
	my $offpn = 1 + length($self->{scid}) if $level == 3;
	$offpn = (
		$offpn = unpack("C", substr($buf, 5, 1)),
		$self->{scid} = substr($buf, 6, $offpn),
		$offpn = unpack("C", substr($buf, 6 + length($self->{scid}), 1)),
		$self->{dcid} =
			substr($buf, 6 + length($self->{scid}) + 1, $offpn),
		7 + ($level == 0) + length($self->{scid})
			+ length($self->{dcid})) if $level != 3;
	my ($len, $val) = $level != 3
		? parse_int(substr($buf, $offpn))
		: (0, length($buf) - $offpn);
	$offpn += $len;

	my $sample = substr($buf, $offpn + 4, 16);
	my ($ad, $pnl, $pn) = $self->decrypt_ad($buf,
		$self->{keys}[$level]{r}{hp}, $sample, $offpn, $level);
	Test::Nginx::log_core('||', "ad = " . unpack("H*", $ad));
	$pn = $self->decode_pn($pn, $pnl, $level);
	my $nonce = substr(pack("x12") . pack("N", $pn), -12)
		^ $self->{keys}[$level]{r}{iv};
	my $ciphertext = substr($buf, $offpn + $pnl, $val - 16 - $pnl);
	my $tag = substr($buf, $offpn + $val - 16, 16);
	my ($f, @args) = decrypt_aead_f($level, $self->{cipher});
	my $plaintext = $f->(@args,
		$self->{keys}[$level]{r}{key}, $nonce, $ad, $ciphertext, $tag);
	if ($level == 3 && $self->{keys}[4]) {
		if (!defined $plaintext) {
			# in-flight packets might be protected with old keys
			$nonce = substr(pack("x12") . pack("N", $pn), -12)
				^ $self->{keys}[4]{r}{iv};
			$plaintext = $f->(@args, $self->{keys}[4]{r}{key},
				$nonce, $ad, $ciphertext, $tag);
		} else {
			# remove old keys after unprotected with new keys
			splice @{$self->{keys}}, 4, 1;
		}
	}
	return if !defined $plaintext;
	Test::Nginx::log_core('||',
		"pn = $pn, level = $level, length = " . length($plaintext));

	$self->{pn}[1][$level] = $pn;
	$self->{ack}[$level]{$pn} = -1;
	$self->{ack}[$_] = undef for (0 .. $level - 1);

	return ($level, $plaintext,
		substr($buf, length($ad . $ciphertext . $tag)), '');
}

sub decrypt_ad {
	my ($self, $buf, $hp, $sample, $offset, $level) = @_;

	goto aes if $level == 0 || $self->{cipher} != 0x1303;

	my $counter = unpack("V", substr($sample, 0, 4));
	my $nonce = substr($sample, 4, 12);
	my $stream = Crypt::Stream::ChaCha->new($hp, $nonce, $counter);
	my $mask = $stream->crypt($self->{zero});
	goto mask;
aes:
	my $m = Crypt::Mode::CTR->new('AES');
	$mask = $m->encrypt($self->{zero}, $hp, $sample);
mask:
	substr($buf, 0, 1) ^= substr($mask, 0, 1)
		& ($level == 3 ? "\x1f" : "\x0f");
	my $pnl = unpack("C", substr($buf, 0, 1) & "\x03") + 1;
	substr($buf, $offset, $pnl) ^= substr($mask, 1);

	my $pn = 0;
	for my $n (1 .. $pnl) {
		$pn += unpack("C", substr($buf, $offset + $n - 1, 1))
			<< ($pnl - $n) * 8;
	}

	my $ad = substr($buf, 0, $offset + $pnl);
	return ($ad, $pnl, $pn);
}

sub encrypt_aead_f {
	my ($level, $cipher) = @_;
	if ($level == 0 || $cipher == 0x1301 || $cipher == 0x1302) {
		return \&Crypt::AuthEnc::GCM::gcm_encrypt_authenticate, 'AES';
	}
	if ($cipher == 0x1304) {
		return \&Crypt::AuthEnc::CCM::ccm_encrypt_authenticate, 'AES';
	}
	\&Crypt::AuthEnc::ChaCha20Poly1305::chacha20poly1305_encrypt_authenticate;
}

sub encrypt_aead {
	my ($self, $payload, $level) = @_;

	if ($level == 0) {
		my $padding = 1200 - length($payload);
		$padding = 0 if $padding < 0;
		$payload = $payload . pack("x$padding");
	}

	my $pn = ++$self->{pn}[0][$level];
	my $ad = pack("C", $level == 3
		? 0x40 | ($self->{key_phase} << 2)
		: 0xc + $level << 4) | "\x03";
	$ad .= "\x00\x00\x00\x01" unless $level == 3;
	$ad .= $level == 3 ? $self->{dcid} :
		pack("C", length($self->{dcid})) . $self->{dcid}
		. pack("C", length($self->{scid})) . $self->{scid};
	$ad .= build_int(length($self->{token})) . $self->{token}
		if $level == 0;
	$ad .= build_int(length($payload) + 16 + 4) unless $level == 3;
	$ad .= pack("N", $pn);
	my $nonce = substr(pack("x12") . pack("N", $pn), -12)
		^ $self->{keys}[$level]{w}{iv};
	my ($f, @args) = encrypt_aead_f($level, $self->{cipher});
	my @taglen = ($level != 0 && $self->{cipher} == 0x1304) ? 16 : ();
	my ($ciphertext, $tag) = $f->(@args,
		$self->{keys}[$level]{w}{key}, $nonce, $ad, @taglen, $payload);
	my $sample = substr($ciphertext . $tag, 0, 16);

	$ad = $self->encrypt_ad($ad, $self->{keys}[$level]{w}{hp},
		$sample, $level);
	return $ad . $ciphertext . $tag;
}

sub encrypt_ad {
	my ($self, $ad, $hp, $sample, $level) = @_;

	goto aes if $level == 0 || $self->{cipher} != 0x1303;

	my $counter = unpack("V", substr($sample, 0, 4));
	my $nonce = substr($sample, 4, 12);
	my $stream = Crypt::Stream::ChaCha->new($hp, $nonce, $counter);
	my $mask = $stream->crypt($self->{zero});
	goto mask;
aes:
	my $m = Crypt::Mode::CTR->new('AES');
	$mask = $m->encrypt($self->{zero}, $hp, $sample);
mask:
	substr($ad, 0, 1) ^= substr($mask, 0, 1)
		& ($level == 3 ? "\x1f" : "\x0f");
	substr($ad, -4) ^= substr($mask, 1);
	return $ad;
}

sub decrypt_retry {
	my ($self, $buf) = @_;
	my $off = unpack("C", substr($buf, 5, 1));
	$self->{scid} = substr($buf, 6, $off);
	$self->{odcid} = $self->{dcid};
	$self->{dcid} = unpack("C", substr($buf, 6 + $off, 1));
	$self->{dcid} = substr($buf, 6 + $off + 1, $self->{dcid});
	my $token = substr($buf, 6 + $off + 1 + length($self->{dcid}), -16);
	my $tag = substr($buf, -16);
	my $pseudo = pack("C", length($self->{odcid})) . $self->{odcid}
		. substr($buf, 0, -16);
	$self->{retry} = { token => $token, tag => $tag, pseudo => $pseudo };
	return $tag, '', $token;
}

sub retry_token {
	my ($self) = @_;
	return $self->{retry}{token};
}

sub retry_tag {
	my ($self) = @_;
	return $self->{retry}{tag};
}

sub retry_verify_tag {
	my ($self) = @_;
	my $key = "\xbe\x0c\x69\x0b\x9f\x66\x57\x5a"
		. "\x1d\x76\x6b\x54\xe3\x68\xc8\x4e";
	my $nonce = "\x46\x15\x99\xd3\x5d\x63\x2b\xf2\x23\x98\x25\xbb";
	my (undef, $tag) = Crypt::AuthEnc::GCM::gcm_encrypt_authenticate('AES',
		$key, $nonce, $self->{retry}{pseudo}, '');
	return $tag;
}

sub set_traffic_keys {
	my ($self, $label, $hash, $hlen, $level, $direction, $secret, $digest)
		= @_;
	my $prk = hkdf_expand_label($label, $hash, $hlen, $secret, $digest);
	my $klen = $self->{cipher} == 0x1301 || $self->{cipher} == 0x1304
		? 16 : 32;
	my $key = hkdf_expand_label("tls13 quic key", $hash, $klen, $prk);
	my $iv = hkdf_expand_label("tls13 quic iv", $hash, 12, $prk);
	my $hp = hkdf_expand_label("tls13 quic hp", $hash, $klen, $prk);
	$self->{keys}[$level]{$direction}{prk} = $prk;
	$self->{keys}[$level]{$direction}{key} = $key;
	$self->{keys}[$level]{$direction}{iv} = $iv;
	$self->{keys}[$level]{$direction}{hp} = $hp;
}

sub key_update {
	my ($self) = @_;
	my ($prk, $key, $iv);
	my $klen = $self->{cipher} == 0x1301 || $self->{cipher} == 0x1304
		? 16 : 32;
	my ($hash, $hlen) = $self->{cipher} == 0x1302 ?
		('SHA384', 48) : ('SHA256', 32);
	$self->{key_phase} ^= 1;

	for my $direction ('r', 'w') {
		$prk = $self->{keys}[3]{$direction}{prk};
		$prk = hkdf_expand_label("tls13 quic ku", $hash, $hlen, $prk);
		$key = hkdf_expand_label("tls13 quic key", $hash, $klen, $prk);
		$iv = hkdf_expand_label("tls13 quic iv", $hash, 12, $prk);
		$self->{keys}[4]{$direction}{key} =
			$self->{keys}[3]{$direction}{key};
		$self->{keys}[4]{$direction}{iv} =
			$self->{keys}[3]{$direction}{iv};
		$self->{keys}[3]{$direction}{prk} = $prk;
		$self->{keys}[3]{$direction}{key} = $key;
		$self->{keys}[3]{$direction}{iv} = $iv;
	}
}

sub hmac_finished {
	my ($hash, $hlen, $key, $digest) = @_;
	my $expand = hkdf_expand_label("tls13 finished", $hash, $hlen, $key);
	Crypt::Mac::HMAC::hmac($hash, $expand, $digest);
}

sub tls13_finished {
	my $hmac = hmac_finished(@_);
	"\x14\x00" . pack('n', length($hmac)) . $hmac;
}

sub binders {
	my $hmac = hmac_finished(@_);
	pack('n', length($hmac) + 1) . pack('C', length($hmac)) . $hmac;
}

sub hkdf_advance {
	my ($hash, $hlen, $secret, $prk) = @_;
	my $expand = hkdf_expand_label("tls13 derived", $hash, $hlen, $prk,
		Crypt::Digest::digest_data($hash, ''));
	Crypt::KeyDerivation::hkdf_extract($secret, $expand, $hash);
}

sub hkdf_expand_label {
	my ($label, $hash, $len, $prk, $context) = @_;
	$context = '' if !defined $context;
	my $info = pack("C3", 0, $len, length($label)) . $label
		. pack("C", length($context)) . $context;
	Crypt::KeyDerivation::hkdf_expand($prk, $hash, $len, $info);
}

sub ext_key_share {
	my ($extens) = @_;
	my $offset = 0;
	while ($offset < length($extens)) {
		my $ext = substr($extens, $offset, 2);
		my $len = unpack("C", substr($extens, $offset + 2, 1)) * 8 +
			unpack("C", substr($extens, $offset + 3, 1));
		if ($ext eq "\x00\x33") {
			return substr($extens, $offset + 4 + 4, $len - 4);
		}
		$offset += 4 + $len;
	}
}

sub ext_early_data {
	my ($extens) = @_;
	my $offset = 0;
	while ($offset < length($extens)) {
		my $ext = substr($extens, $offset, 2);
		my $len = unpack("C", substr($extens, $offset + 2, 1)) * 8 +
			unpack("C", substr($extens, $offset + 3, 1));
		if ($ext eq "\x00\x2a") {
			return substr($extens, $offset + 4, $len);
		}
		$offset += 4 + $len;
	}
}

sub ext_pre_shared_key {
	my ($extens) = @_;
	my $offset = 0;
	while ($offset < length($extens)) {
		my $ext = substr($extens, $offset, 2);
		my $len = unpack("C", substr($extens, $offset + 2, 1)) * 8 +
			unpack("C", substr($extens, $offset + 3, 1));
		if ($ext eq "\x00\x29") {
			return unpack("n", substr($extens, $offset + 4, $len));
		}
		$offset += 4 + $len;
	}
	return;
}

sub ext_transport_parameters {
	my ($extens) = @_;
	my $offset = 0;

	while ($offset < length($extens)) {
		my $ext = substr($extens, $offset, 2);
		my $len = unpack("C", substr($extens, $offset + 2, 1)) * 8 +
			unpack("C", substr($extens, $offset + 3, 1));
		if ($ext eq "\x00\x39") {
			return substr($extens, $offset + 4, $len);
		}
		$offset += 4 + $len;
	}
	return;
}

###############################################################################

sub build_cc {
	my ($code, $reason) = @_;
	"\x1d" . build_int($code) . build_int(length($reason)) . $reason;
}

sub build_ack {
	my ($ack) = @_;
	my @keys = sort { $b <=> $a } keys %$ack;

	return "\x02" . build_int($keys[0]) . "\x00\x00\x00" if @keys == 1;

	my $min = my $max = shift @keys;
	my @acks = ();
	for my $next (@keys) {
		if ($next == $min - 1) {
			$min = $next;
			next if $next != $keys[-1];
		}
		push @acks, $max, $min;
		$min = $max = $next;
	}

	($max, $min) = splice @acks, 0, 2;
	my $ranges = @acks / 2;

	$ack = "\x02" . build_int($max) . "\x00" . build_int($ranges)
		. build_int($max - $min);

	for (my $smallest = $min; $ranges--; ) {
		my ($max, $min) = splice @acks, 0, 2;
		$ack .= build_int($smallest - $max - 2);
		$ack .= build_int($max - $min);
		$smallest = $min;
	}

	return $ack;
}

sub build_crypto {
	my ($tlsm) = @_;
	"\x06\x00" . build_int(length($tlsm)) . $tlsm;
}

sub build_stream {
	my ($self, $r, %extra) = @_;
	my $stream = $extra{start} ? 0xe : 0xf;
	my $length = $extra{length} ? $extra{length} : build_int(length($r));
	my $offset = build_int($extra{offset} ? $extra{offset} : 0);
	my $sid = defined $extra{sid} ? $extra{sid} : 4 * $self->{requests}++;
	$sid = build_int($sid);
	pack("C", $stream) . $sid . $offset . $length . $r;
}

sub parse_int {
	my ($buf) = @_;
	return undef if length($buf) < 1;

	my $val = unpack("C", substr($buf, 0, 1));
	my $len = my $plen = 1 << ($val >> 6);
	return undef if length($buf) < $len;

	$val = $val & 0x3f;
	while (--$len) {
		$val = ($val << 8) + unpack("C", substr($buf, $plen - $len, 1))
	}
	return ($plen, $val);
}

sub build_int {
	my ($value) = @_;

	my $build_int_set = sub {
		my ($value, $len, $bits) = @_;
		(($value >> ($len * 8)) & 0xff) | ($bits << 6);
	};

	if ($value < 1 << 6) {
		pack("C", $build_int_set->($value, 0, 0));

	} elsif ($value < 1 << 14) {
		pack("C*",
			$build_int_set->($value, 1, 1),
			$build_int_set->($value, 0, 0),
		);

	} elsif ($value < 1 << 30) {
		pack("C*",
			$build_int_set->($value, 3, 2),
			$build_int_set->($value, 2, 0),
			$build_int_set->($value, 1, 0),
			$build_int_set->($value, 0, 0),
		);

	} else {
		pack("C*",
			$build_int_set->($value, 7, 3),
			$build_int_set->($value, 6, 0),
			$build_int_set->($value, 5, 0),
			$build_int_set->($value, 4, 0),
			$build_int_set->($value, 3, 0),
			$build_int_set->($value, 2, 0),
			$build_int_set->($value, 1, 0),
			$build_int_set->($value, 0, 0),
		);
	}
}

###############################################################################

sub read_stream_message {
	my ($self, $timo) = @_;
	my ($level, $plaintext, @data);
	my $s = $self->{socket};

	while (1) {
		@data = $self->parse_stream();
		return @data if @data;
		return if scalar @{$self->{frames_in}};

again:
		my $txt;

		if (!length($self->{buf})) {
			return unless IO::Select->new($s)->can_read($timo || 3);
			$s->sysread($self->{buf}, 65527);
			$txt = "recv";
		} else {
			$txt =  "remaining";
		}
		my $len = length $self->{buf};
		Test::Nginx::log_core('||', sprintf("$txt = [%d]", $len));

		while ($self->{buf}) {
			($level, $plaintext, $self->{buf}, $self->{token})
				= $self->decrypt_aead($self->{buf});
			if (!defined $plaintext) {
				$self->{buf} = '';
				goto again;
			}
			$self->retry(), return if $self->{token};
			$self->handle_frames(parse_frames($plaintext), $level);
			@data = $self->parse_stream();
			return @data if @data;
			return if scalar @{$self->{frames_in}};
		}
	}
	return;
}

sub parse_stream {
	my ($self) = @_;
	my $data;

	for my $i (0 .. $#{$self->{stream_in}}) {
		my $stream = $self->{stream_in}[$i];
		next if !defined $stream;

		my $offset = $stream->{buf}[0][0];
		next if $offset != 0;

		my $buf = $stream->{buf}[0][2];

		if ($stream->{buf}[0][3]) {
			$stream->{buf}[0][3] = 0;
			$stream->{eof} = 1;
			$data = '';
		}

		if (length($buf) > $stream->{pos}) {
			$data = substr($buf, $stream->{pos});
			$stream->{pos} = length($buf);
		}

		next if !defined $data;

		return ($i, $data, $stream->{eof} ? 1 : 0);
	}
	return;
}

###############################################################################

sub read_tls_message {
	my ($self, $buf, $type) = @_;
	my $s = $self->{socket};

	while (!$type->($self)) {
		my $txt;

		if (!length($$buf)) {
			return unless IO::Select->new($s)->can_read(3);
			$s->sysread($$buf, 65527);
			$txt = "recv";
		} else {
			$txt = "remaining";
		}
		my $len = length $$buf;
		Test::Nginx::log_core('||', sprintf("$txt = [%d]", $len));

		while ($$buf) {
			(my $level, my $plaintext, $$buf, $self->{token})
				= $self->decrypt_aead($$buf);
			return if !defined $plaintext;
			$self->retry(), return 1 if $self->{token};
			$self->handle_frames(parse_frames($plaintext), $level);
			return 1 if $type->($self);
		}
	}
	return;
}

sub parse_tls_server_hello {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[0][0][2] if $self->{crypto_in}[0][0];
	return 0 if !$buf || length($buf) < 4;
	my $type = unpack("C", substr($buf, 0, 1));
	my $len = unpack("n", substr($buf, 2, 2));
	my $content = substr($buf, 4, $len);
	return 0 if length($content) < $len;
	$self->{tlsm}{sh} = substr($buf, 0, 4) . $content;
	return $self->{tlsm}{sh};
}

sub parse_tls_encrypted_extensions {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[2][0][2] if $self->{crypto_in}[2][0];
	return 0 if !$buf;
	my $off = 0;
	my $content;

	while ($off < length($buf)) {
		return 0 if length($buf) < 4;
		my $type = unpack("C", substr($buf, $off, 1));
		my $len = unpack("n", substr($buf, $off + 2, 2));
		$content = substr($buf, $off + 4, $len);
		return 0 if length($content) < $len;
		last if $type == 8;
		$off += 4 + $len;
	}
	$self->{tlsm}{ee} = substr($buf, $off, 4) . $content;
	return $self->{tlsm}{ee};
}

sub parse_tls_certificate {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[2][0][2] if $self->{crypto_in}[2][0];
	return 0 if !$buf;
	my $off = 0;
	my $content;

	while ($off < length($buf)) {
		return 0 if length($buf) < 4;
		my $type = unpack("C", substr($buf, $off, 1));
		my $len = unpack("n", substr($buf, $off + 2, 2));
		$content = substr($buf, $off + 4, $len);
		return 0 if length($content) < $len;
		last if $type == 11 || $type == 25;
		$off += 4 + $len;
	}
	$self->{tlsm}{cert} = substr($buf, $off, 4) . $content;
	return $self->{tlsm}{cert};
}

sub parse_tls_certificate_verify {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[2][0][2] if $self->{crypto_in}[2][0];
	return 0 if !$buf;
	my $off = 0;
	my $content;

	while ($off < length($buf)) {
		return 0 if length($buf) < 4;
		my $type = unpack("C", substr($buf, $off, 1));
		my $len = unpack("n", substr($buf, $off + 2, 2));
		$content = substr($buf, $off + 4, $len);
		return 0 if length($content) < $len;
		last if $type == 15;
		$off += 4 + $len;
	}
	$self->{tlsm}{cv} = substr($buf, $off, 4) . $content;
	return $self->{tlsm}{cv};
}

sub parse_tls_finished {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[2][0][2] if $self->{crypto_in}[2][0];
	return 0 if !$buf;
	my $off = 0;
	my $content;

	while ($off < length($buf)) {
		return 0 if length($buf) < 4;
		my $type = unpack("C", substr($buf, $off, 1));
		my $len = unpack("n", substr($buf, $off + 2, 2));
		$content = substr($buf, $off + 4, $len);
		return 0 if length($content) < $len;
		last if $type == 20;
		$off += 4 + $len;
	}
	$self->{tlsm}{sf} = substr($buf, $off, 4) . $content;
	return $self->{tlsm}{sf};
}

sub parse_tls_nst {
	my ($self) = @_;
	my $buf = $self->{crypto_in}[3][0][2] if $self->{crypto_in}[3][0];
	return 0 if !$buf;
	my $off = 0;
	my $content;

	while ($off < length($buf)) {
		return 0 if length($buf) < 4;
		my $type = unpack("C", substr($buf, $off, 1));
		my $len = unpack("n", substr($buf, $off + 2, 2));
		$content = substr($buf, $off + 4, $len);
		return 0 if length($content) < $len;
		$self->{tlsm}{nst} .= substr($buf, $off, 4) . $content;
		$self->save_session_tickets(substr($buf, $off, 4) . $content);
		$off += 4 + $len;
		substr($self->{crypto_in}[3][0][2], 0, $off) = '';
	}
}

sub build_tls_client_hello {
	my ($self) = @_;
	my $named_group = $self->tls_named_group();
	my $key_share = $self->tls_public_key();

	my $version = "\x03\x03";
	my $random = Crypt::PRNG::random_bytes(32);
	my $session = "\x00";
	my $cipher = pack('n', length($self->{ciphers})) . $self->{ciphers};
	my $compr = "\x01\x00";
	my $ext = build_tlsext_server_name($self->{sni})
		. build_tlsext_supported_groups($named_group)
		. build_tlsext_alpn("h3", "hq-interop")
		. build_tlsext_sigalgs(0x0804, 0x0805, 0x0806)
		. build_tlsext_certcomp(@{$self->{ccomp}})
		. build_tlsext_supported_versions(0x0304)
		. build_tlsext_ke_modes(1)
		. build_tlsext_key_share($named_group, $key_share)
		. build_tlsext_quic_tp($self->{scid}, $self->{opts});

	$ext .= build_tlsext_early_data($self->{psk})
		. build_tlsext_psk($self->{psk}) if keys %{$self->{psk}};

	my $len = pack('n', length($ext));
	my $ch = $version . $random . $session . $cipher . $compr . $len . $ext;
	$ch = "\x01\x00" . pack('n', length($ch)) . $ch;
	$ch = build_tls_ch_with_binder($ch, $self->{psk}, $self->{es_prk})
		if keys %{$self->{psk}};
	return $ch;
}

sub build_tlsext_server_name {
	my ($name) = @_;
	return '' if !defined $name;
	my $sname = pack('xn', length($name)) . $name;
	my $snamelist = pack('n', length($sname)) . $sname;
	pack('n2', 0, length($snamelist)) . $snamelist;
}

sub build_tlsext_supported_groups {
	my $ngrouplist = pack('n*', @_ * 2, @_);
	pack('n2', 10, length($ngrouplist)) . $ngrouplist;
}

sub build_tlsext_alpn {
	my $protoname = pack('(C/a*)*', @_);
	my $protonamelist = pack('n', length($protoname)) . $protoname;
	pack('n2', 16, length($protonamelist)) . $protonamelist;
}

sub build_tlsext_sigalgs {
	my $sschemelist = pack('n*', @_ * 2, @_);
	pack('n2', 13, length($sschemelist)) . $sschemelist;
}

sub build_tlsext_certcomp {
	return '' unless scalar @_;

	my $ccalgs = pack('Cn*', @_ * 2, @_);
	pack('n2', 27, length($ccalgs)) . $ccalgs;
}

sub build_tlsext_supported_versions {
	my $versions = pack('Cn*', @_ * 2, @_);
	pack('n2', 43, length($versions)) . $versions;
}

sub build_tlsext_ke_modes {
	my $versions = pack('C*', scalar(@_), @_);
	pack('n2', 45, length($versions)) . $versions;
}

sub build_tlsext_key_share {
	my ($group, $share) = @_;
	my $kse = pack("n2", $group, length($share)) . $share;
	my $ksch = pack("n", length($kse)) . $kse;
	pack('n2', 51, length($ksch)) . $ksch;
}

sub build_tlsext_quic_tp {
	my ($scid, $opts) = @_;
	my $tp = '';
	my $quic_tp_tlv = sub {
		my ($id, $val) = @_;
		$val = $opts->{$id} // $val;
		$val = build_int($val) unless $id == 15;
		$tp .= build_int($id) . pack("C*", length($val)) . $val;
	};
	$quic_tp_tlv->(1, 30000);
	$quic_tp_tlv->(4, 1048576);
	$quic_tp_tlv->(5, 262144);
	$quic_tp_tlv->(7, 262144);
	$quic_tp_tlv->(9, 100);
	$quic_tp_tlv->(15, $scid);
	pack('n2', 57, length($tp)) . $tp;
}

sub build_tlsext_early_data {
	my ($psk) = @_;
	$psk->{ed} ? pack('n2', 42, 0) : '';
}

sub build_tlsext_psk {
	my ($psk) = @_;
	my $identity = pack('n', length($psk->{ticket})) . $psk->{ticket}
		. $psk->{age_add};
	my $identities = pack('n', length($identity)) . $identity;
	my $hash = $psk->{cipher} == 0x1302 ? pack('x48') : pack('x32');
	my $binder = pack('C', length($hash)) . $hash;
	my $binders = pack('n', length($binder)) . $binder;
	pack('n2', 41, length($identities . $binders)) . $identities . $binders;
}

sub build_tls_ch_with_binder {
	my ($ch, $psk, $prk) = @_;
	my ($hash, $hlen) = $psk->{cipher} == 0x1302 ?
		('SHA384', 48) : ('SHA256', 32);
	my $key = hkdf_expand_label("tls13 res binder", $hash, $hlen, $prk,
		Crypt::Digest::digest_data($hash, ''));
	my $truncated = substr($ch, 0, -3 - $hlen);
	my $context = Crypt::Digest::digest_data($hash, $truncated);
	$truncated . binders($hash, $hlen, $key, $context);
}

sub tls_generate_key {
	my ($self) = @_;
	$self->{sk} = $self->{group} eq 'x25519'
		? Crypt::PK::X25519->new->generate_key
		: Crypt::PK::ECC->new->generate_key($self->{group});
}

sub tls_public_key {
	my ($self) = @_;
	$self->{sk}->export_key_raw('public');
}

sub tls_shared_secret {
	my ($self, $pub) = @_;
	my $pk = $self->{group} eq 'x25519'
		? Crypt::PK::X25519->new : Crypt::PK::ECC->new;
	$pk->import_key_raw($pub, $self->{group} eq 'x25519'
		? 'public' : $self->{group});
	$self->{sk}->shared_secret($pk);
}

sub tls_named_group {
	my ($self) = @_;
	my $name = $self->{group};
	return 0x17 if $name eq 'secp256r1';
	return 0x18 if $name eq 'secp384r1';
	return 0x19 if $name eq 'secp521r1';
	return 0x1d if $name eq 'x25519';
}

###############################################################################

1;

###############################################################################
