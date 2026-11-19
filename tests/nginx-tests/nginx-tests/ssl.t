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
use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl rewrite proxy socket_ssl/)
	->has_daemon('openssl')->plan(21);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    log_format ssl $ssl_protocol;

    server {
        listen       127.0.0.1:8085 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key inner.key;
        ssl_certificate inner.crt;
        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;
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
        listen       127.0.0.1:8086 ssl;
        server_name  localhost;

        ssl_session_cache shared:SSL:1m;
        ssl_session_tickets on;
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
x509_extensions = myca_extensions
[ req_distinguished_name ]
[ myca_extensions ]
basicConstraints = critical,CA:TRUE
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

$t->run();

###############################################################################

# ssl session reuse

my $ctx = get_ssl_context();

like(get('/', 8085, $ctx), qr/^body \.$/m, 'session');

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();

like(get('/', 8085, $ctx), qr/^body r$/m, 'session reused');

}

# ssl certificate inheritance

my $s = get_ssl_socket(8086);
like($s->dump_peer_certificate(), qr/CN=localhost/, 'CN');

$s = get_ssl_socket(8085);
like($s->dump_peer_certificate(), qr/CN=inner/, 'CN inner');

# session timeout

$ctx = get_ssl_context();

get('/', 8086, $ctx);
select undef, undef, undef, 2.1;

like(get('/', 8086, $ctx), qr/^body \.$/m, 'session timeout');

# embedded variables

$ctx = get_ssl_context();
like(get('/id', 8085, $ctx), qr/^body (\w{64})?$/m, 'session id');

TODO: {
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL') && test_tls13();
local $TODO = 'no TLSv1.3 sessions ids in BoringSSL'
	if $t->has_module('BoringSSL|AWS-LC') && test_tls13();

like(get('/id', 8085, $ctx), qr/^body \w{64}$/m, 'session id reused');

}

unlike(http_get('/id'), qr/body \w/, 'session id no ssl');

like(get('/cipher', 8085), qr/^body [\w-]+$/m, 'cipher');

SKIP: {
skip 'BoringSSL', 1 if $t->has_module('BoringSSL|AWS-LC');

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
$s = undef;
is(() = $r =~ /(200 OK)/g, 1000, 'pipelined requests');

# OpenSSL 3.0 error "unexpected eof while reading" seen as a critical error

ok(get_ssl_socket(8085), 'ssl unexpected eof');

# close_notify is sent before lingering close

ok(get_ssl_shutdown(8085), 'ssl shutdown on lingering close');

$t->stop();

like($t->read_file('ssl.log'), qr/^(TLS|SSL)v(\d|\.)+$/m,
	'log ssl variable on lingering close');

like(`grep -F '[crit]' ${\($t->testdir())}/error.log`, qr/^$/s, 'no crit');

###############################################################################

sub test_tls13 {
	return get('/protocol', 8085) =~ /TLSv1.3/;
}

sub get {
	my ($uri, $port, $ctx, %extra) = @_;
	my $s = get_ssl_socket($port, $ctx, %extra) or return;
	return http_get($uri, socket => $s);
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
	return $r;
}

sub cert {
	my ($uri, $port) = @_;
	return get(
		$uri, $port, undef,
		SSL_cert_file => "$d/subject.crt",
		SSL_key_file => "$d/subject.key"
	);
}

sub get_ssl_context {
	return IO::Socket::SSL::SSL_Context->new(
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_session_cache_size => 100
	);
}

sub get_ssl_socket {
	my ($port, $ctx, %extra) = @_;
	return http(
		'', PeerAddr => '127.0.0.1:' . port($port), start => 1,
		SSL => 1,
		SSL_reuse_ctx => $ctx,
		%extra
	);
}

sub get_ssl_shutdown {
	my ($port) = @_;

	my $s = http(
		'GET /' . CRLF . 'extra',
		PeerAddr => '127.0.0.1:' . port($port), start => 1,
		SSL => 1
	);

	$s->blocking(0);
	while (IO::Select->new($s)->can_read(8)) {
		my $n = $s->sysread(my $buf, 16384);
		next if !defined $n && $!{EWOULDBLOCK};
		last;
	}
	$s->blocking(1);

	return $s->stop_SSL();
}

###############################################################################
