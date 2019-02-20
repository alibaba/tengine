#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module.

###############################################################################

use warnings;
use strict;

use Test::More;

use POSIX qw/ mkfifo /;
use Socket qw/ :DEFAULT $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
};
plan(skip_all => 'Net::SSLeay not installed') if $@;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/stream stream_ssl/)->has_daemon('openssl');

$t->plan(7)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_session_tickets off;

    # inherited by server "inherits"
    ssl_password_file password_stream;

    server {
        listen      127.0.0.1:8080 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache builtin;
        ssl_password_file password;
    }

    server {
        listen      127.0.0.1:8082 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache off;
        ssl_password_file password_many;
    }

    server {
        listen      127.0.0.1:8083 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache builtin:1000;
        ssl_password_file password_fifo;
    }

    server {
        listen      127.0.0.1:8084 ssl;
        proxy_pass  127.0.0.1:8081;

        ssl_session_cache shared:SSL:1m;
        ssl_certificate_key inherits.key;
        ssl_certificate inherits.crt;
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();
mkfifo("$d/password_fifo", 0700);

foreach my $name ('localhost', 'inherits') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 1024 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}


my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");

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

my ($s, $ssl, $ses);

($s, $ssl) = get_ssl_socket(port(8080));
Net::SSLeay::write($ssl, "GET / HTTP/1.0$CRLF$CRLF");
like(Net::SSLeay::read($ssl), qr/200 OK/, 'ssl');

# ssl_session_cache

($s, $ssl) = get_ssl_socket(port(8080));
$ses = Net::SSLeay::get_session($ssl);

($s, $ssl) = get_ssl_socket(port(8080), $ses);
is(Net::SSLeay::session_reused($ssl), 1, 'builtin session reused');

($s, $ssl) = get_ssl_socket(port(8082));
$ses = Net::SSLeay::get_session($ssl);

($s, $ssl) = get_ssl_socket(port(8082), $ses);
isnt(Net::SSLeay::session_reused($ssl), 1, 'session not reused');

($s, $ssl) = get_ssl_socket(port(8083));
$ses = Net::SSLeay::get_session($ssl);

($s, $ssl) = get_ssl_socket(port(8083), $ses);
is(Net::SSLeay::session_reused($ssl), 1, 'builtin size session reused');

($s, $ssl) = get_ssl_socket(port(8084));
$ses = Net::SSLeay::get_session($ssl);

($s, $ssl) = get_ssl_socket(port(8084), $ses);
is(Net::SSLeay::session_reused($ssl), 1, 'shared session reused');

# ssl_certificate inheritance

($s, $ssl) = get_ssl_socket(port(8080));
like(Net::SSLeay::dump_peer_certificate($ssl), qr/CN=localhost/, 'CN');

($s, $ssl) = get_ssl_socket(port(8084));
like(Net::SSLeay::dump_peer_certificate($ssl), qr/CN=inherits/, 'CN inner');

###############################################################################

sub get_ssl_socket {
	my ($port, $ses) = @_;
	my $s;

	my $dest_ip = inet_aton('127.0.0.1');
	my $dest_serv_params = sockaddr_in($port, $dest_ip);

	socket($s, &AF_INET, &SOCK_STREAM, 0) or die "socket: $!";
	connect($s, $dest_serv_params) or die "connect: $!";

	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_session($ssl, $ses) if defined $ses;
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
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
