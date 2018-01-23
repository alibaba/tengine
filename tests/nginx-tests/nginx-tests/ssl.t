#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for http ssl module.

###############################################################################

use warnings;
use strict;

use Test::More;

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

my $t = Test::Nginx->new()->has(qw/http http_ssl rewrite/)
	->has_daemon('openssl');

$t->plan(18)->write_file_expand('nginx.conf', <<'EOF');

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
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_certificate_key inner.key;
        ssl_certificate inner.crt;
        ssl_session_cache shared:SSL:1m;

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
    }

    server {
        listen      127.0.0.1:8081;
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
        listen      127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_session_cache builtin:1000;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen      127.0.0.1:8083 ssl;
        server_name  localhost;

        ssl_session_cache none;

        location / {
            return 200 "body $ssl_session_reused";
        }
    }

    server {
        listen      127.0.0.1:8084 ssl;
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
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost', 'inner') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

my $ctx = new IO::Socket::SSL::SSL_Context(
	SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
	SSL_session_cache_size => 100);

$t->run();

###############################################################################

like(http_get('/reuse', socket => get_ssl_socket($ctx)), qr/^body \.$/m,
	'shared initial session');
like(http_get('/reuse', socket => get_ssl_socket($ctx)), qr/^body r$/m,
	'shared session reused');

like(http_get('/', socket => get_ssl_socket($ctx, 8081)), qr/^body \.$/m,
	'builtin initial session');
like(http_get('/', socket => get_ssl_socket($ctx, 8081)), qr/^body r$/m,
	'builtin session reused');

like(http_get('/', socket => get_ssl_socket($ctx, 8082)), qr/^body \.$/m,
	'builtin size initial session');
like(http_get('/', socket => get_ssl_socket($ctx, 8082)), qr/^body r$/m,
	'builtin size session reused');

like(http_get('/', socket => get_ssl_socket($ctx, 8083)), qr/^body \.$/m,
	'reused none initial session');
like(http_get('/', socket => get_ssl_socket($ctx, 8083)), qr/^body \.$/m,
	'session not reused 1');

like(http_get('/', socket => get_ssl_socket($ctx, 8084)), qr/^body \.$/m,
	'reused off initial session');
like(http_get('/', socket => get_ssl_socket($ctx, 8084)), qr/^body \.$/m,
	'session not reused 2');

# ssl certificate inheritance

my $s = get_ssl_socket($ctx, 8081);
like($s->dump_peer_certificate(), qr/CN=localhost/, 'CN');

$s->close();

$s = get_ssl_socket($ctx);
like($s->dump_peer_certificate(), qr/CN=inner/, 'CN inner');

$s->close();

# session timeout

select undef, undef, undef, 2.1;

like(http_get('/', socket => get_ssl_socket($ctx, 8081)), qr/^body \.$/m,
	'session timeout');

# embedded variables

my ($sid) = http_get('/id', socket => get_ssl_socket($ctx)) =~ /^body (\w+)$/m;
is(length $sid, 64, 'session id');

unlike(http_get('/id'), qr/body \w/, 'session id no ssl');

like(http_get('/cipher', socket => get_ssl_socket($ctx)),
	qr/^body [\w-]+$/m, 'cipher');

like(http_get('/client_verify', socket => get_ssl_socket($ctx)),
	qr/^body NONE$/m, 'client verify');

like(http_get('/protocol', socket => get_ssl_socket($ctx)),
	qr/^body (TLS|SSL)v(\d|\.)+$/m, 'protocol');

###############################################################################

sub get_ssl_socket {
	my ($ctx, $port) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(2);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => $port || '8443',
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_reuse_ctx => $ctx,
			SSL_error_trap => sub { die $_[1] }
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
