#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream ssl module, ssl_conf_command.

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
	->has(qw/stream stream_ssl stream_return openssl:1.0.2/)
	->has(qw/socket_ssl_reused/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen       127.0.0.1:8443 ssl;
        return       OK;

        ssl_protocols TLSv1.2;

        ssl_session_tickets off;
        ssl_conf_command Options SessionTicket;

        ssl_prefer_server_ciphers on;
        ssl_conf_command Options -ServerPreference;
        ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
        ssl_conf_command Certificate override.crt;
        ssl_conf_command PrivateKey override.key;
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

foreach my $name ('localhost', 'override') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->try_run('no ssl_conf_command')->plan(3);

###############################################################################

my $s;

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8443),
	SSL => 1,
	SSL_session_cache_size => 100
);
$s->read();

like($s->socket()->dump_peer_certificate(), qr/CN=override/, 'Certificate');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8443),
	SSL => 1,
	SSL_reuse_ctx => $s->socket()
);
ok($s->socket()->get_session_reused(), 'SessionTicket');

$s = stream(
	PeerAddr => '127.0.0.1:' . port(8443),
	SSL => 1,
	SSL_cipher_list =>
		'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384'
);
is($s->socket()->get_cipher(),
	'ECDHE-RSA-AES128-GCM-SHA256', 'ServerPreference');

###############################################################################
