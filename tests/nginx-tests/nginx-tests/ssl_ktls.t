#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for http ssl module, lingering close with kernel TLS.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl/)
	->has_daemon('openssl');

plan(skip_all => 'no Linux KTLS') unless -r '/proc/net/tls_stat';

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        ssl_conf_command Options KTLS;

        lingering_close always;
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

$t->write_file('index.html', 'SEE-THIS');
$t->try_run('no ssl_conf_command')->plan(1);

###############################################################################

# the connection is closed after the response, the client "close notify"
# alert is read during lingering close

my $rx = tls_rx();
like(http_get('/', SSL => 1), qr/200 OK/, 'response');

$t->todo_alerts() if tls_rx() > $rx && !$t->has_version('1.31.8');

###############################################################################

sub tls_rx {
	open my $fh, '<', '/proc/net/tls_stat' or return 0;
	my ($n) = map { /^TlsRxSw\s+(\d+)/ ? $1 : () } <$fh>;
	return $n || 0;
}

###############################################################################
