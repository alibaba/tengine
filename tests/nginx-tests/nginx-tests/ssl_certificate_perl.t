#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, loading certificates from memory with perl module.

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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl perl openssl:1.0.2 socket_ssl_sni/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    perl_set $pem '
        sub {
            my $r = shift;
            local $/;
            my $sni = $r->variable("ssl_server_name");
            open my $fh, "<", "%%TESTDIR%%/$sni.crt";
            my $content = <$fh>;
            close $fh;
            return $content;
        }
    ';

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate data:$pem;
        ssl_certificate_key data:$pem;
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
		. "-out $d/$name.crt -keyout $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run()->plan(2);

###############################################################################

like(cert('one'), qr/CN=one/, 'certificate');
like(cert('two'), qr/CN=two/, 'certificate 2');

###############################################################################

sub cert {
	my $s = get_socket(@_) || return;
	return $s->dump_peer_certificate();
}

sub get_socket {
	my $host = shift;
	return http_get('/', start => 1, SSL => 1, SSL_hostname => $host);
}

###############################################################################
