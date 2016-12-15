package Test::Nginx::HTTP2;

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Module for nginx HTTP/2 tests.

###############################################################################

use warnings;
use strict;

use Test::More qw//;
use IO::Select;
use IO::Socket;
use Socket qw/ CRLF /;
use Data::Dumper;

use Test::Nginx;

my %cframe = (
	0 => { name => 'DATA', value => \&data },
	1 => { name => 'HEADERS', value => \&headers },
#	2 => { name => 'PRIORITY', value => \&priority },
	3 => { name => 'RST_STREAM', value => \&rst_stream },
	4 => { name => 'SETTINGS', value => \&settings },
#	5 => { name => 'PUSH_PROMISE', value => \&push_promise },
	6 => { name => 'PING', value => \&ping },
	7 => { name => 'GOAWAY', value => \&goaway },
	8 => { name => 'WINDOW_UPDATE', value => \&window_update },
	9 => { name => 'CONTINUATION', value => \&continuation },
);

sub new {
	my $class = shift;
	my ($port, %extra) = @_;

	my $s = $extra{socket} || new_socket($port, %extra);
	my $preface = $extra{preface}
		|| 'PRI * HTTP/2.0' . CRLF . CRLF . 'SM' . CRLF . CRLF;

	if ($extra{proxy}) {
		raw_write($s, $extra{proxy});
	}

	# preface

	raw_write($s, $preface);

	my $self = bless {
		socket => $s, last_stream => -1,
		dynamic_encode => [ static_table() ],
		dynamic_decode => [ static_table() ],
		static_table_size => scalar @{[static_table()]},
		iws => 65535, conn_window => 65535, streams => {}
	}, $class;

	return $self if $extra{pure};

	# update windows, if any

	my $frames = $self->read(all => [
		{ type => 'WINDOW_UPDATE' },
		{ type => 'SETTINGS'}
	]);

	# 6.5.3.  Settings Synchronization

	if (grep { $_->{type} eq "SETTINGS" && $_->{flags} == 0 } @$frames) {
		$self->h2_settings(1);
	}

	return $self;
}

sub h2_ping {
	my ($self, $payload) = @_;

	raw_write($self->{socket}, pack("x2C2x5a8", 8, 0x6, $payload));
}

sub h2_rst {
	my ($self, $stream, $error) = @_;

	raw_write($self->{socket}, pack("x2C2xNN", 4, 0x3, $stream, $error));
}

sub h2_goaway {
	my ($self, $stream, $lstream, $err, $debug, %extra) = @_;
	$debug = '' unless defined $debug;
	my $len = defined $extra{len} ? $extra{len} : 8 + length($debug);
	my $buf = pack("x2C2xN3A*", $len, 0x7, $stream, $lstream, $err, $debug);

	my @bufs = map {
		raw_write($self->{socket}, substr $buf, 0, $_, "");
		select undef, undef, undef, 0.2;
	} @{$extra{split}};

	raw_write($self->{socket}, $buf);
}

sub h2_priority {
	my ($self, $w, $stream, $dep, %extra) = @_;

	$stream = 0 unless defined $stream;
	$dep = 0 unless defined $dep;
	$dep |= $extra{excl} << 31 if exists $extra{excl};
	raw_write($self->{socket}, pack("x2C2xNNC", 5, 0x2, $stream, $dep, $w));
}

sub h2_window {
	my ($self, $win, $stream) = @_;

	$stream = 0 unless defined $stream;
	raw_write($self->{socket}, pack("x2C2xNN", 4, 0x8, $stream, $win));
}

sub h2_settings {
	my ($self, $ack, %extra) = @_;

	my $len = 6 * keys %extra;
	my $buf = pack_length($len) . pack "CCx4", 0x4, $ack ? 0x1 : 0x0;
	$buf .= join '', map { pack "nN", $_, $extra{$_} } keys %extra;
	raw_write($self->{socket}, $buf);
}

sub h2_unknown {
	my ($self, $payload) = @_;

	my $buf = pack_length(length($payload)) . pack("Cx5a*", 0xa, $payload);
	raw_write($self->{socket}, $buf);
}

sub h2_continue {
	my ($ctx, $stream, $uri) = @_;

	$uri->{h2_continue} = 1;
	return new_stream($ctx, $uri, $stream);
}

sub h2_body {
	my ($self, $body, $extra) = @_;
	$extra = {} unless defined $extra;

	my $len = length $body;
	my $sid = $self->{last_stream};

	if ($len > $self->{conn_window} || $len > $self->{streams}{$sid}) {
		$self->read(all => [{ type => 'WINDOW_UPDATE' }]);
	}

	if ($len > $self->{conn_window} || $len > $self->{streams}{$sid}) {
		return;
	}

	$self->{conn_window} -= $len;
	$self->{streams}{$sid} -= $len;

	my $buf;

	my $split = ref $extra->{body_split} && $extra->{body_split} || [];
	for (@$split) {
		$buf .= pack_body($self, substr($body, 0, $_, ""), 0x0, $extra);
	}

	$buf .= pack_body($self, $body, 0x1, $extra) if defined $body;

	$split = ref $extra->{split} && $extra->{split} || [];
	for (@$split) {
		raw_write($self->{socket}, substr($buf, 0, $_, ""));
		return if $extra->{abort};
		select undef, undef, undef, ($extra->{split_delay} || 0.2);
	}

	raw_write($self->{socket}, $buf);
}

sub new_stream {
	my ($self, $uri, $stream) = @_;
	my ($input, $buf);
	my ($d, $status);

	$self->{headers} = '';

	my $host = $uri->{host} || 'localhost';
	my $method = $uri->{method} || 'GET';
	my $scheme = $uri->{scheme} || 'http';
	my $path = $uri->{path} || '/';
	my $headers = $uri->{headers};
	my $body = $uri->{body};
	my $prio = $uri->{prio};
	my $dep = $uri->{dep};

	my $pad = defined $uri->{padding} ? $uri->{padding} : 0;
	my $padlen = defined $uri->{padding} ? 1 : 0;

	my $type = defined $uri->{h2_continue} ? 0x9 : 0x1;
	my $flags = defined $uri->{continuation} ? 0x0 : 0x4;
	$flags |= 0x1 unless defined $body || defined $uri->{body_more};
	$flags |= 0x8 if $padlen;
	$flags |= 0x20 if defined $dep || defined $prio;

	if ($stream) {
		$self->{last_stream} = $stream;
	} else {
		$self->{last_stream} += 2;
		$self->{streams}{$self->{last_stream}} = $self->{iws};
	}

	$buf = pack("xxx");				# Length stub
	$buf .= pack("CC", $type, $flags);		# END_HEADERS
	$buf .= pack("N", $self->{last_stream});	# Stream-ID

	$dep = 0 if defined $prio and not defined $dep;
	$prio = 16 if defined $dep and not defined $prio;

	unless ($headers) {
		$input = hpack($self, ":method", $method);
		$input .= hpack($self, ":scheme", $scheme);
		$input .= hpack($self, ":path", $path);
		$input .= hpack($self, ":authority", $host);
		$input .= hpack($self, "content-length", length($body))
			if $body;

	} else {
		$input = join '', map {
			hpack($self, $_->{name}, $_->{value},
			mode => $_->{mode}, huff => $_->{huff})
		} @$headers if $headers;
	}

	$input = pack("B*", '001' . ipack(5, $uri->{table_size})) . $input
		if defined $uri->{table_size};

	my $split = ref $uri->{continuation} && $uri->{continuation} || [];
	my @input = map { substr $input, 0, $_, "" } @$split;
	push @input, $input;

	# set length, attach headers, padding, priority

	my $hlen = length($input[0]) + $pad + $padlen;
	$hlen += 5 if $flags & 0x20;
	$buf |= pack_length($hlen);

	$buf .= pack 'C', $pad if $padlen;		# Pad Length?
	$buf .= pack 'NC', $dep, $prio if $flags & 0x20;
	$buf .= $input[0];
	$buf .= (pack 'C', 0) x $pad if $padlen;	# Padding

	shift @input;

	while (@input) {
		$input = shift @input;
		$flags = @input ? 0x0 : 0x4;
		$buf .= pack_length(length($input));
		$buf .= pack("CC", 0x9, $flags);
		$buf .= pack("N", $self->{last_stream});
		$buf .= $input;
	}

	$split = ref $uri->{body_split} && $uri->{body_split} || [];
	for (@$split) {
		$buf .= pack_body($self, substr($body, 0, $_, ""), 0x0, $uri);
	}

	$buf .= pack_body($self, $body, 0x1, $uri) if defined $body;

	$split = ref $uri->{split} && $uri->{split} || [];
	for (@$split) {
		raw_write($self->{socket}, substr($buf, 0, $_, ""));
		goto done if $uri->{abort};
		select undef, undef, undef, ($uri->{split_delay} || 0.2);
	}

	raw_write($self->{socket}, $buf);
done:
	return $self->{last_stream};
}

sub read {
	my ($self, %extra) = @_;
	my (@got);
	my $s = $self->{socket};
	my $buf = '';
	my $wait = $extra{wait};

	local $Data::Dumper::Terse = 1;

	while (1) {
		$buf = raw_read($s, $buf, 9, $wait);
		last if length $buf < 9;

		my $length = unpack_length($buf);
		my $type = unpack('x3C', $buf);
		my $flags = unpack('x4C', $buf);

		my $stream = unpack "x5 B32", $buf;
		substr($stream, 0, 1) = 0;
		$stream = unpack("N", pack("B32", $stream));

		$buf = raw_read($s, $buf, $length + 9, $wait);
		last if length($buf) < $length + 9;

		$buf = substr($buf, 9);

		my $frame = $cframe{$type}{value}($self, $buf, $length, $flags,
			$stream);
		$frame->{length} = $length;
		$frame->{type} = $cframe{$type}{name};
		$frame->{flags} = $flags;
		$frame->{sid} = $stream;
		push @got, $frame;

		Test::Nginx::log_core('||', $_) for split "\n", Dumper $frame;

		$buf = substr($buf, $length);

		last unless $extra{all} && test_fin($got[-1], $extra{all});
	};
	return \@got;
}

###############################################################################

sub pack_body {
	my ($ctx, $body, $flags, $extra) = @_;

	my $pad = defined $extra->{body_padding} ? $extra->{body_padding} : 0;
	my $padlen = defined $extra->{body_padding} ? 1 : 0;

	my $buf = pack_length(length($body) + $pad + $padlen);
	$flags |= 0x8 if $padlen;
	vec($flags, 0, 1) = 0 if $extra->{body_more};
	$buf .= pack 'CC', 0x0, $flags;		# DATA, END_STREAM
	$buf .= pack 'N', $ctx->{last_stream};
	$buf .= pack 'C', $pad if $padlen;	# DATA Pad Length?
	$buf .= $body;
	$buf .= pack "x$pad" if $padlen;	# DATA Padding
	return $buf;
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
		&& $_->{sid} == $frame->{sid} && $_->{fin} & $frame->{flags})
	} @test if defined $frame->{flags};

	# wait for the specified frame

	@test = grep { !($_->{type} && $_->{type} eq $frame->{type}) } @test;

	@{$all} = @test;
}

sub headers {
	my ($ctx, $buf, $len, $flags) = @_;
	$ctx->{headers} = substr($buf, 0, $len);
	return unless $flags & 0x4;
	{ headers => hunpack($ctx, $buf, $len) };
}

sub continuation {
	my ($ctx, $buf, $len, $flags) = @_;
	$ctx->{headers} .= substr($buf, 0, $len);
	return unless $flags & 0x4;
	{ headers => hunpack($ctx, $ctx->{headers}, length($ctx->{headers})) };
}

sub data {
	my ($ctx, $buf, $len) = @_;
	return { data => substr($buf, 0, $len) };
}

sub settings {
	my ($ctx, $buf, $len) = @_;
	my %payload;
	my $skip = 0;

	for (1 .. $len / 6) {
		my $id = hex unpack "\@$skip n", $buf; $skip += 2;
		$payload{$id} = unpack "\@$skip N", $buf; $skip += 4;

		$ctx->{iws} = $payload{$id} if $id == 4;
	}
	return \%payload;
}

sub ping {
	my ($ctx, $buf, $len) = @_;
	return { value => unpack "A$len", $buf };
}

sub rst_stream {
	my ($ctx, $buf, $len) = @_;
	return { code => unpack "N", $buf };
}

sub goaway {
	my ($ctx, $buf, $len) = @_;
	my %payload;

	my $stream = unpack "B32", $buf;
	substr($stream, 0, 1) = 0;
	$stream = unpack("N", pack("B32", $stream));
	$payload{last_sid} = $stream;

	$len -= 4;
	$payload{code} = unpack "x4 N", $buf;
	$payload{debug} = unpack "x8 A$len", $buf;
	return \%payload;
}

sub window_update {
	my ($ctx, $buf, $len, $flags, $sid) = @_;
	my $value = unpack "B32", $buf;
	substr($value, 0, 1) = 0;
	$value = unpack("N", pack("B32", $value));

	unless ($sid) {
		$ctx->{conn_window} += $value;

	} else {
		$ctx->{streams}{$sid} = $ctx->{iws}
			unless defined $ctx->{streams}{$sid};
		$ctx->{streams}{$sid} += $value;
	}

	return { wdelta => $value };
}

sub pack_length {
	pack 'c3', unpack 'xc3', pack 'N', $_[0];
}

sub unpack_length {
	unpack 'N', pack 'xc3', unpack 'c3', $_[0];
}

sub raw_read {
	my ($s, $buf, $len, $timo) = @_;
	$timo = 5 unless $timo;
	my $got = '';

	while (length($buf) < $len && IO::Select->new($s)->can_read($timo)) {
		$s->sysread($got, 16384) or last;
		log_in($got);
		$buf .= $got;
	}
	return $buf;
}

sub raw_write {
	my ($s, $message) = @_;

	local $SIG{PIPE} = 'IGNORE';

	while (IO::Select->new($s)->can_write(0.4)) {
		log_out($message);
		my $n = $s->syswrite($message);
		last unless $n;
		$message = substr($message, $n);
		last unless length $message;
	}
}

sub new_socket {
	my ($port, %extra) = @_;
	my $npn = $extra{'npn'};
	my $alpn = $extra{'alpn'};
	my $s;

	$port ||= port(8080);

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => "127.0.0.1:$port",
		);
		require IO::Socket::SSL if $extra{'SSL'};
		IO::Socket::SSL->start_SSL($s,
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_npn_protocols => $npn ? [ $npn ] : undef,
			SSL_alpn_protocols => $alpn ? [ $alpn ] : undef,
			SSL_error_trap => sub { die $_[1] }
		) if $extra{'SSL'};
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub static_table {
	[ '',			''		], # unused
	[ ':authority',		''		],
	[ ':method',		'GET'		],
	[ ':method',		'POST'		],
	[ ':path',		'/'		],
	[ ':path',		'/index.html'	],
	[ ':scheme',		'http'		],
	[ ':scheme',		'https'		],
	[ ':status',		'200'		],
	[ ':status',		'204'		],
	[ ':status',		'206'		],
	[ ':status',		'304'		],
	[ ':status',		'400'		],
	[ ':status',		'404'		],
	[ ':status',		'500'		],
	[ 'accept-charset',	''		],
	[ 'accept-encoding',	'gzip, deflate'	],
	[ 'accept-language',	''		],
	[ 'accept-ranges',	''		],
	[ 'accept',		''		],
	[ 'access-control-allow-origin',
				''		],
	[ 'age',		''		],
	[ 'allow',		''		],
	[ 'authorization',	''		],
	[ 'cache-control',	''		],
	[ 'content-disposition',
				''		],
	[ 'content-encoding',	''		],
	[ 'content-language',	''		],
	[ 'content-length',	''		],
	[ 'content-location',	''		],
	[ 'content-range',	''		],
	[ 'content-type',	''		],
	[ 'cookie',		''		],
	[ 'date',		''		],
	[ 'etag',		''		],
	[ 'expect',		''		],
	[ 'expires',		''		],
	[ 'from',		''		],
	[ 'host',		''		],
	[ 'if-match',		''		],
	[ 'if-modified-since',	''		],
	[ 'if-none-match',	''		],
	[ 'if-range',		''		],
	[ 'if-unmodified-since',
				''		],
	[ 'last-modified',	''		],
	[ 'link',		''		],
	[ 'location',		''		],
	[ 'max-forwards',	''		],
	[ 'proxy-authenticate',	''		],
	[ 'proxy-authorization',
				''		],
	[ 'range',		''		],
	[ 'referer',		''		],
	[ 'refresh',		''		],
	[ 'retry-after',	''		],
	[ 'server',		''		],
	[ 'set-cookie',		''		],
	[ 'strict-transport-security',
				''		],
	[ 'transfer-encoding',	''		],
	[ 'user-agent',		''		],
	[ 'vary',		''		],
	[ 'via',		''		],
	[ 'www-authenticate',	''		],
}

# RFC 7541, 5.1.  Integer Representation

sub ipack {
	my ($base, $d) = @_;
	return sprintf("%.*b", $base, $d) if $d < 2**$base - 1;

	my $o = sprintf("%${base}b", 2**$base - 1);
	$d -= 2**$base - 1;
	while ($d >= 128) {
		$o .= sprintf("%8b", $d % 128 + 128);
		$d /= 128;
	}
	$o .= sprintf("%08b", $d);
	return $o;
}

sub iunpack {
	my ($base, $b, $s) = @_;

	my $len = unpack("\@$s B8", $b); $s++;
	my $prefix = substr($len, 0, 8 - $base);
	$len = '0' x (8 - $base) . substr($len, 8 - $base);
	$len = unpack("C", pack("B8", $len));

	return ($len, $s, $prefix) if $len < 2**$base - 1;

	my $m = 0;
	my $d;

	do {
		$d = unpack("\@$s C", $b); $s++;
		$len += ($d & 127) * 2**$m;
		$m += $base;
	} while (($d & 128) == 128);

	return ($len, $s, $prefix);
}

sub hpack {
	my ($ctx, $name, $value, %extra) = @_;
	my $table = $ctx->{dynamic_encode};
	my $mode = defined $extra{mode} ? $extra{mode} : 1;
	my $huff = $extra{huff};

	my ($index, $buf) = 0;

	# 6.1.  Indexed Header Field Representation

	if ($mode == 0) {
		++$index until $index > $#$table
			or $table->[$index][0] eq $name
			and $table->[$index][1] eq $value;
		$buf = pack('B*', '1' . ipack(7, $index));
	}

	# 6.2.1.  Literal Header Field with Incremental Indexing

	if ($mode == 1) {
		splice @$table, $ctx->{static_table_size}, 0, [ $name, $value ];

		++$index until $index > $#$table
			or $table->[$index][0] eq $name;
		my $value = $huff ? huff($value) : $value;

		$buf = pack('B*', '01' . ipack(6, $index)
			. ($huff ? '1' : '0') . ipack(7, length($value)));
		$buf .= $value;
	}

	# 6.2.1.  Literal Header Field with Incremental Indexing -- New Name

	if ($mode == 2) {
		splice @$table, $ctx->{static_table_size}, 0, [ $name, $value ];

		my $name = $huff ? huff($name) : $name;
		my $value = $huff ? huff($value) : $value;
		my $hbit = ($huff ? '1' : '0');

		$buf = pack('B*', '01000000');
		$buf .= pack('B*', $hbit . ipack(7, length($name)));
		$buf .= $name;
		$buf .= pack('B*', $hbit . ipack(7, length($value)));
		$buf .= $value;
	}

	# 6.2.2.  Literal Header Field without Indexing

	if ($mode == 3) {
		++$index until $index > $#$table
			or $table->[$index][0] eq $name;
		my $value = $huff ? huff($value) : $value;

		$buf = pack('B*', '0000' . ipack(4, $index)
			. ($huff ? '1' : '0') . ipack(7, length($value)));
		$buf .= $value;
	}

	# 6.2.2.  Literal Header Field without Indexing -- New Name

	if ($mode == 4) {
		my $name = $huff ? huff($name) : $name;
		my $value = $huff ? huff($value) : $value;
		my $hbit = ($huff ? '1' : '0');

		$buf = pack('B*', '00000000');
		$buf .= pack('B*', $hbit . ipack(7, length($name)));
		$buf .= $name;
		$buf .= pack('B*', $hbit . ipack(7, length($value)));
		$buf .= $value;
	}

	# 6.2.3.  Literal Header Field Never Indexed

	if ($mode == 5) {
		++$index until $index > $#$table
			or $table->[$index][0] eq $name;
		my $value = $huff ? huff($value) : $value;

		$buf = pack('B*', '0001' . ipack(4, $index)
			. ($huff ? '1' : '0') . ipack(7, length($value)));
		$buf .= $value;
	}

	# 6.2.3.  Literal Header Field Never Indexed -- New Name

	if ($mode == 6) {
		my $name = $huff ? huff($name) : $name;
		my $value = $huff ? huff($value) : $value;
		my $hbit = ($huff ? '1' : '0');

		$buf = pack('B*', '00010000');
		$buf .= pack('B*', $hbit . ipack(7, length($name)));
		$buf .= $name;
		$buf .= pack('B*', $hbit . ipack(7, length($value)));
		$buf .= $value;
	}

	return $buf;
}

sub hunpack {
	my ($ctx, $data, $length) = @_;
	my $table = $ctx->{dynamic_decode};
	my %headers;
	my $skip = 0;
	my ($index, $name, $value);

	my $field = sub {
		my ($b) = @_;
		my ($len, $s, $huff) = iunpack(7, @_);

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

		if (substr($ib, 0, 1) eq '1') {
			($index, $skip) = iunpack(7, $data, $skip);
			$add->(\%headers,
				$table->[$index][0], $table->[$index][1]);
			next;
		}

		if (substr($ib, 0, 2) eq '01') {
			($index, $skip) = iunpack(6, $data, $skip);
			$name = $table->[$index][0];

			($name, $skip) = $field->($data, $skip) unless $name;
			($value, $skip) = $field->($data, $skip);

			splice @$table,
				$ctx->{static_table_size}, 0, [ $name, $value ];
			$add->(\%headers, $name, $value);
			next;
		}

		if (substr($ib, 0, 4) eq '0000') {
			($index, $skip) = iunpack(4, $data, $skip);
			$name = $table->[$index][0];

			($name, $skip) = $field->($data, $skip) unless $name;
			($value, $skip) = $field->($data, $skip);

			$add->(\%headers, $name, $value);
			next;
		}
		last;
	}

	return \%headers;
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

###############################################################################

1;

###############################################################################
