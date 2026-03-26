#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module.

###############################################################################

use warnings;
use strict;

use Test::More;

use POSIX qw/ mkfifo /;
use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/stream stream_ssl socket_ssl/)
	->has_daemon('openssl');

$t->plan(5)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    # inherited by server "inherits"
    ssl_password_file password_stream;

    server {
        listen      127.0.0.1:8443 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_password_file password;
    }

    server {
        listen      127.0.0.1:8444 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_password_file password_many;
    }

    server {
        listen      127.0.0.1:8445 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_password_file password_fifo;
    }

    server {
        listen      127.0.0.1:8446 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_certificate_key inherits.key;
        ssl_certificate inherits.crt;
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
mkfifo("$d/password_fifo", 0700);

foreach my $name ('localhost', 'inherits') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('password', 'localhost');
$t->write_file('password_many', "wrong$CRLF" . "localhost$CRLF");
$t->write_file('password_stream', 'inherits');

my $p = fork();
exec("echo localhost > $d/password_fifo") if $p == 0;

$t->run_daemon(\&http_daemon);

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
kill 'INT', $p if $@;

$t->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

like(get(8443), qr/200 OK/, 'ssl');
like(get(8444), qr/200 OK/, 'ssl password many');
like(get(8445), qr/200 OK/, 'ssl password fifo');

# ssl_certificate inheritance

like(cert(8443), qr/CN=localhost/, 'CN');
like(cert(8446), qr/CN=inherits/, 'CN inner');

###############################################################################

sub get {
	my $s = get_socket(@_);
	return $s->io("GET / HTTP/1.0$CRLF$CRLF");
}

sub cert {
	my $s = get_socket(@_);
	return $s->socket()->dump_peer_certificate();
}

sub get_socket {
	my ($port) = @_;
	return stream(PeerAddr => '127.0.0.1:' . port($port), SSL => 1);
}

###############################################################################

sub http_daemon {
	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1:' . port(8081),
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	local $SIG{PIPE} = 'IGNORE';

	while (my $client = $server->accept()) {
		$client->autoflush(1);

		while (<$client>) {
			last if (/^\x0d?\x0a?$/);
		}

		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close

EOF

		close $client;
	}
}

###############################################################################
