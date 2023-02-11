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

eval {
	require Net::SSLeay;
	Net::SSLeay::load_error_strings();
	Net::SSLeay::SSLeay_add_ssl_algorithms();
	Net::SSLeay::randomize();
};
plan(skip_all => 'Net::SSLeay not installed') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

my $t = Test::Nginx->new()->has(qw/http http_ssl perl/)->has_daemon('openssl');

$t->{_configure_args} =~ /OpenSSL ([\d\.]+)/;
plan(skip_all => 'OpenSSL too old') unless defined $1 and $1 ge '1.0.2';

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
        listen       127.0.0.1:8080 ssl;
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

like(cert('one', 8080), qr/CN=one/, 'certificate');
like(cert('two', 8080), qr/CN=two/, 'certificate 2');

###############################################################################

sub cert {
	my ($host, $port) = @_;
	my ($s, $ssl) = get_ssl_socket($host, $port) or return;
	Net::SSLeay::dump_peer_certificate($ssl);
}

sub get_ssl_socket {
	my ($host, $port) = @_;

	my $s = IO::Socket::INET->new('127.0.0.1:' . port($port));
	my $ctx = Net::SSLeay::CTX_new() or die("Failed to create SSL_CTX $!");
	my $ssl = Net::SSLeay::new($ctx) or die("Failed to create SSL $!");
	Net::SSLeay::set_tlsext_host_name($ssl, $host);
	Net::SSLeay::set_fd($ssl, fileno($s));
	Net::SSLeay::connect($ssl) or die("ssl connect");
	return ($s, $ssl);
}

###############################################################################
