#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module with dynamic certificates.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/stream stream_ssl stream_geo stream_return openssl:1.0.2/)
	->has(qw/socket_ssl_sni/)
	->has_daemon('openssl')
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    geo $one {
        default one;
    }

    geo $two {
        default two;
    }

    geo $pass {
        default pass;
    }

    ssl_session_cache shared:SSL:1m;
    ssl_session_tickets on;

    server {
        listen       127.0.0.1:8080 ssl;
        return       $ssl_server_name:$ssl_session_reused:$ssl_protocol;

        ssl_certificate $one.crt;
        ssl_certificate_key $one.key;
    }

    server {
        listen       127.0.0.1:8083 ssl;
        return       $ssl_server_name:$ssl_session_reused;

        # found in key
        ssl_certificate pass.crt;
        ssl_certificate_key $pass.key;
        ssl_password_file password_file;
    }

    server {
        listen       127.0.0.1:8081 ssl;
        return       $ssl_server_name:$ssl_session_reused;

        ssl_certificate $one.crt;
        ssl_certificate_key $one.key;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        return       $ssl_server_name:$ssl_session_reused;

        ssl_certificate $two.crt;
        ssl_certificate_key $two.key;
    }

    server {
        listen       127.0.0.1:8084 ssl;
        return       $ssl_server_name:$ssl_session_reused;

        ssl_certificate $ssl_server_name.crt;
        ssl_certificate_key $ssl_server_name.key;
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

foreach my $name ('one', 'two') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('pass') {
	system("openssl genrsa -out $d/$name.key -passout pass:pass "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create $name key: $!\n";
	system("openssl req -x509 -new -config $d/openssl.conf "
		. "-subj /CN=$name/ -out $d/$name.crt -key $d/$name.key "
		. "-passin pass:pass >>$d/openssl.out 2>&1") == 0
		or die "Can't create $name certificate: $!\n";
}

$t->write_file('password_file', 'pass');
$t->write_file('index.html', '');

$t->run()->plan(7);

###############################################################################

like(cert('default', 8080), qr/CN=one/, 'default certificate');
like(get('default', 8080), qr/default/, 'default context');

like(get('password', 8083), qr/password/, 'ssl_password_file');

# session reuse

my $s = session('default', 8080);

TODO: {
local $TODO = 'no TLSv1.3 sessions, old Net::SSLeay'
	if $Net::SSLeay::VERSION < 1.88 && test_tls13();
local $TODO = 'no TLSv1.3 sessions, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 2.061 && test_tls13();

like(get('default', 8080, $s), qr/default:r/, 'session reused');

TODO: {
local $TODO = 'no SSL_session_key, old IO::Socket::SSL'
	if $IO::Socket::SSL::VERSION < 1.965;

like(get('default', 8081, $s), qr/default:r/, 'session id context match');

}
}

like(get('default', 8082, $s), qr/default:\./, 'session id context distinct');

# errors

ok(!get('nx', 8084), 'no certificate');

###############################################################################

sub get {
	my $s = get_socket(@_) || return;
	return $s->read();
}

sub cert {
	my $s = get_socket(@_) || return;
	return $s->socket()->dump_peer_certificate();
}

sub session {
	my $s = get_socket(@_);
	$s->read();
	return $s->socket();
}

sub get_socket {
	my ($host, $port, $ctx) = @_;
	return stream(
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1,
		SSL_hostname => $host,
		SSL_session_cache_size => 100,
		SSL_session_key => 1,
		SSL_reuse_ctx => $ctx
	);
}

sub test_tls13 {
	return get('default', 8080) =~ /TLSv1.3/;
}

###############################################################################
