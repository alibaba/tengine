#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module with haproxy protocol to ssl backend.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CR LF CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl socket_ssl/)
	->has_daemon('openssl')->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    proxy_ssl       on;
    proxy_protocol  on;

    server {
        listen          127.0.0.1:8080;
        proxy_pass      127.0.0.1:8081;
    }

    server {
        listen          127.0.0.1:8082;
        proxy_pass      127.0.0.1:8083;
        proxy_protocol  off;
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run_daemon(\&stream_daemon_ssl, port(8081), path => $d, pp => 1);
$t->run_daemon(\&stream_daemon_ssl, port(8083), path => $d, pp => 0);
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8083));

###############################################################################

my $dp = port(8080);

my %r = pp_get('test', '127.0.0.1:' . $dp);
is($r{'data'}, "PROXY TCP4 127.0.0.1 127.0.0.1 $r{'sp'} $dp" . CRLF . 'test',
	'protocol on');

%r = pp_get('test', '127.0.0.1:' . port(8082));
is($r{'data'}, 'test', 'protocol off');

###############################################################################

sub pp_get {
	my ($data, $peer) = @_;

	my $s = http($data, socket => getconn($peer), start => 1);
	my $sockport = $s->sockport();
	$data = http_end($s);
	return ('data' => $data, 'sp' => $sockport);
}

sub getconn {
	my $peer = shift;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => $peer
	)
		or die "Can't connect to nginx: $!\n";

	return $s;
}

###############################################################################

sub stream_daemon_ssl {
	my ($port, %extra) = @_;
	my $d = $extra{path};
	my $pp = $extra{pp};
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => "127.0.0.1:$port",
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		my ($buffer, $data) = ('', '');
		$client->autoflush(1);

		log2c("(new connection $client on $port)");

		# read no more than haproxy header of variable length

		while ($pp) {
			my $prev = $buffer;
			$client->sysread($buffer, 1) or last;
			$data .= $buffer;
			last if $prev eq CR && $buffer eq LF;
		}

		log2i("$client $data");

		# would fail on waitforsocket

		eval {
			IO::Socket::SSL->start_SSL($client,
				SSL_server => 1,
				SSL_cert_file => "$d/localhost.crt",
				SSL_key_file => "$d/localhost.key",
				SSL_error_trap => sub { die $_[1] }
			);
		};
		next if $@;

		$client->sysread($buffer, 65536) or next;

		log2i("$client $buffer");

		$data .= $buffer;

		log2o("$client $data");

		$client->syswrite($data);

		close $client;
	}
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
