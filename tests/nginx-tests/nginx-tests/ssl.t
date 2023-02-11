#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for http ssl module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Socket::SSL; };
plan(skip_all => 'IO::Socket::SSL not installed') if $@;
eval { IO::Socket::SSL::SSL_VERIFY_NONE(); };
plan(skip_all => 'IO::Socket::SSL too old') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl rewrite proxy/)
	->has_daemon('openssl')->plan(28);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_session_tickets off;

    log_format ssl $ssl_protocol;

    server {
        listen       127.0.0.1:8085 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key inner.key;
        ssl_certificate inner.crt;
        ssl_session_cache shared:SSL:1m;
        ssl_verify_client optional_no_ca;

        keepalive_requests 1000;

        location / {
            return 200 "body $ssl_session_reused";
        }
        location /id {
            return 200 "body $ssl_session_id";
        }
        location /cipher {
            return 200 "body $ssl_cipher";
        }
        location /ciphers {
            return 200 "body $ssl_ciphers";
        }
        location /client_verify {
            return 200 "body $ssl_client_verify";
        }
        location /protocol {
            return 200 "body $ssl_protocol";
        }
        location /issuer {
            return 200 "body $ssl_client_i_dn:$ssl_client_i_dn_legacy";
        }
        location /subject {
            return 200 "body $ssl_client_s_dn:$ssl_client_s_dn_legacy";
        }
        location /time {
            return 200 "body $ssl_client_v_start!$ssl_client_v_end!$ssl_client_v_remain";
        }

        location /body {
            add_header X-Body $request_body always;
            proxy_pass http://127.0.0.1:8080/;

            access_log %%TESTDIR%%/ssl.log ssl;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        # Special case for enabled "ssl" directive.

        ssl on;
        ssl_session_cache builtin;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_session_cache builtin:1000;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8083 ssl;
        server_name  localhost;

        ssl_session_cache none;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8084 ssl;
        server_name  localhost;

        ssl_session_cache off;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen       127.0.0.1:8086 ssl;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_timeout 1;

        location / {
            return 200 "body $ssl_session_reused";
        }
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

$t->write_file('ca.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha256
policy = myca_policy
serial = $d/certserial
default_days = 3

[ myca_policy ]
commonName = supplied
EOF

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

system('openssl req -x509 -new '
	. "-config $d/openssl.conf -subj /CN=issuer/ "
	. "-out $d/issuer.crt -keyout $d/issuer.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate for issuer: $!\n";

system("openssl req -new "
	. "-config $d/openssl.conf -subj /CN=subject/ "
	. "-out $d/subject.csr -keyout $d/subject.key "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create certificate for subject: $!\n";

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/issuer.key -cert $d/issuer.crt "
	. "-subj /CN=subject/ -in $d/subject.csr -out $d/subject.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for subject: $!\n";

foreach my $name ('localhost', 'inner') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

# suppress deprecation warning

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

###############################################################################

my $ctx;

SKIP: {
skip 'no TLS 1.3 sessions', 6 if get('/protocol', 8085) =~ /TLSv1.3/
	&& ($Net::SSLeay::VERSION < 1.88 || $IO::Socket::SSL::VERSION < 2.061);

$ctx = get_ssl_context();

like(get('/', 8085, $ctx), qr/^body \.$/m, 'cache shared');
like(get('/', 8085, $ctx), qr/^body r$/m, 'cache shared reused');

$ctx = get_ssl_context();

like(get('/', 8081, $ctx), qr/^body \.$/m, 'cache builtin');
like(get('/', 8081, $ctx), qr/^body r$/m, 'cache builtin reused');

$ctx = get_ssl_context();

like(get('/', 8082, $ctx), qr/^body \.$/m, 'cache builtin size');
like(get('/', 8082, $ctx), qr/^body r$/m, 'cache builtin size reused');

}

$ctx = get_ssl_context();

like(get('/', 8083, $ctx), qr/^body \.$/m, 'cache none');
like(get('/', 8083, $ctx), qr/^body \.$/m, 'cache none not reused');

$ctx = get_ssl_context();

like(get('/', 8084, $ctx), qr/^body \.$/m, 'cache off');
like(get('/', 8084, $ctx), qr/^body \.$/m, 'cache off not reused');

# ssl certificate inheritance

my $s = get_ssl_socket(8081);
like($s->dump_peer_certificate(), qr/CN=localhost/, 'CN');

$s->close();

$s = get_ssl_socket(8085);
like($s->dump_peer_certificate(), qr/CN=inner/, 'CN inner');

$s->close();

# session timeout

$ctx = get_ssl_context();

get('/', 8086, $ctx);
select undef, undef, undef, 2.1;

like(get('/', 8086, $ctx), qr/^body \.$/m, 'session timeout');

# embedded variables

like(get('/id', 8085), qr/^body \w{64}$/m, 'session id');
unlike(http_get('/id'), qr/body \w/, 'session id no ssl');
like(get('/cipher', 8085), qr/^body [\w-]+$/m, 'cipher');

SKIP: {
skip 'BoringSSL', 1 if $t->has_module('BoringSSL');

like(get('/ciphers', 8085), qr/^body [:\w-]+$/m, 'ciphers');

}

like(get('/client_verify', 8085), qr/^body NONE$/m, 'client verify');
like(get('/protocol', 8085), qr/^body (TLS|SSL)v(\d|\.)+$/m, 'protocol');
like(cert('/issuer', 8085), qr!^body CN=issuer:/CN=issuer$!m, 'issuer');
like(cert('/subject', 8085), qr!^body CN=subject:/CN=subject$!m, 'subject');
like(cert('/time', 8085), qr/^body [:\s\w]+![:\s\w]+![23]$/m, 'time');

# c->read->ready handling bug in ngx_ssl_recv(), triggered with chunked body

like(get_body('/body', '0123456789', 20, 5), qr/X-Body: (0123456789){100}/,
	'request body chunked');

# pipelined requests

$s = get_ssl_socket(8085);
my $req = <<EOF;
GET / HTTP/1.1
Host: localhost

EOF

$req x= 1000;

my $r = http($req, socket => $s) || "";
is(() = $r =~ /(200 OK)/g, 1000, 'pipelined requests');

# OpenSSL 3.0 error "unexpected eof while reading" seen as a critical error

ok(get_ssl_socket(8085), 'ssl unexpected eof');

# close_notify is sent before lingering close

is(get_ssl_shutdown(8085), 1, 'ssl shutdown on lingering close');

$t->stop();

like($t->read_file('ssl.log'), qr/^(TLS|SSL)v(\d|\.)+$/m,
	'log ssl variable on lingering close');

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crit');

###############################################################################

sub get {
	my ($uri, $port, $ctx) = @_;
	my $s = get_ssl_socket($port, $ctx) or return;
	my $r = http_get($uri, socket => $s);
	$s->close();
	return $r;
}

sub get_body {
	my ($uri, $body, $len, $n) = @_;
	my $s = get_ssl_socket(8085) or return;
	http("GET /body HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF,
		socket => $s, start => 1);
	my $chs = unpack("H*", pack("C", length($body) * $len));
	http($chs . CRLF . $body x $len . CRLF, socket => $s, start => 1)
		for 1 .. $n;
	my $r = http("0" . CRLF . CRLF, socket => $s);
	$s->close();
	return $r;
}

sub cert {
	my ($uri, $port) = @_;
	my $s = get_ssl_socket($port, undef,
		SSL_cert_file => "$d/subject.crt",
		SSL_key_file => "$d/subject.key") or return;
	http_get($uri, socket => $s);
}

sub get_ssl_context {
	return IO::Socket::SSL::SSL_Context->new(
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_session_cache_size => 100
	);
}

sub get_ssl_socket {
	my ($port, $ctx, %extra) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => port($port),
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_reuse_ctx => $ctx,
			SSL_error_trap => sub { die $_[1] },
			%extra
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub get_ssl_shutdown {
	my ($port) = @_;

	my $s = IO::Socket::INET->new('127.0.0.1:' . port($port));
	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	Net::SSLeay::write($ssl, 'GET /' . CRLF . 'extra');
	Net::SSLeay::read($ssl);
	Net::SSLeay::set_shutdown($ssl, 1);
	Net::SSLeay::shutdown($ssl);
}

###############################################################################
