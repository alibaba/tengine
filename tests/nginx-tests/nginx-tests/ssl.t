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
    ssl_session_tickets off;

    server {
        listen       127.0.0.1:8085 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key inner.key;
        ssl_certificate inner.crt;
        ssl_session_cache shared:SSL:1m;
        ssl_verify_client optional_no_ca;

        location /reuse {
            return 200 "body $ssl_session_reused";
        }
        location /id {
            return 200 "body $ssl_session_id";
        }
        location /cipher {
            return 200 "body $ssl_cipher";
        }
        location /client_verify {
            return 200 "body $ssl_client_verify";
        }
        location /protocol {
            return 200 "body $ssl_protocol";
        }
        location /issuer {
            return 200 "body $ssl_client_i_dn";
        }
        location /subject {
            return 200 "body $ssl_client_s_dn";
        }

        location /body {
            add_header X-Body $request_body always;
            proxy_pass http://127.0.0.1:8080/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        # Special case for enabled "ssl" directive.

        ssl on;
        ssl_session_cache builtin;
        ssl_session_timeout 1;

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

$t->write_file('ca.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha1
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

my $ctx = new IO::Socket::SSL::SSL_Context(
	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
	SSL_session_cache_size => 100);

open OLDERR, ">&", \*STDERR; close STDERR;
$t->run();
open STDERR, ">&", \*OLDERR;

###############################################################################

like(get('/reuse', 8085), qr/^body \.$/m, 'shared initial session');
like(get('/reuse', 8085), qr/^body r$/m, 'shared session reused');

like(get('/', 8081), qr/^body \.$/m, 'builtin initial session');
like(get('/', 8081), qr/^body r$/m, 'builtin session reused');

like(get('/', 8082), qr/^body \.$/m, 'builtin size initial session');
like(get('/', 8082), qr/^body r$/m, 'builtin size session reused');

like(get('/', 8083), qr/^body \.$/m, 'reused none initial session');
like(get('/', 8083), qr/^body \.$/m, 'session not reused 1');

like(get('/', 8084), qr/^body \.$/m, 'reused off initial session');
like(get('/', 8084), qr/^body \.$/m, 'session not reused 2');

# ssl certificate inheritance

my $s = get_ssl_socket($ctx, port(8081));
like($s->dump_peer_certificate(), qr/CN=localhost/, 'CN');

$s->close();

$s = get_ssl_socket($ctx, port(8085));
like($s->dump_peer_certificate(), qr/CN=inner/, 'CN inner');

$s->close();

# session timeout

select undef, undef, undef, 2.1;

like(get('/', 8081), qr/^body \.$/m, 'session timeout');

# embedded variables

like(get('/id', 8085), qr/^body \w{64}$/m, 'session id');
unlike(http_get('/id'), qr/body \w/, 'session id no ssl');
like(get('/cipher', 8085), qr/^body [\w-]+$/m, 'cipher');
like(get('/client_verify', 8085), qr/^body NONE$/m, 'client verify');
like(get('/protocol', 8085), qr/^body (TLS|SSL)v(\d|\.)+$/m, 'protocol');
like(cert('/issuer', 8085), qr!^body CN=issuer$!m, 'issuer');
like(cert('/subject', 8085), qr!^body CN=subject$!m, 'subject');

# c->read->ready handling bug in ngx_ssl_recv(), triggered with chunked body

like(get_body('/body', '0123456789', 20, 5), qr/X-Body: (0123456789){100}/,
	'request body chunked');

###############################################################################

sub get {
	my ($uri, $port) = @_;
	my $s = get_ssl_socket($ctx, port($port)) or return;
	my $r = http_get($uri, socket => $s);
	$s->close();
	return $r;
}

sub get_body {
	my ($uri, $body, $len, $n) = @_;
	my $s = get_ssl_socket($ctx, port(8085)) or return;
	http("GET /body HTTP/1.1" . CRLF
		. "Host: localhost" . CRLF
		. "Connection: close" . CRLF
		. "Transfer-Encoding: chunked" . CRLF . CRLF,
		socket => $s, start => 1);
	http("c8" . CRLF . $body x $len . CRLF, socket => $s, start => 1)
		for 1 .. $n;
	my $r = http("0" . CRLF . CRLF, socket => $s);
	$s->close();
	return $r;
}

sub cert {
	my ($uri, $port) = @_;
	my $s = get_ssl_socket(undef, port($port),
		SSL_cert_file => "$d/subject.crt",
		SSL_key_file => "$d/subject.key") or return;
	http_get($uri, socket => $s);
}

sub get_ssl_socket {
	my ($ctx, $port, %extra) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
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

###############################################################################
