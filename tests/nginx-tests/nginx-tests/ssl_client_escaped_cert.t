#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http ssl module, $ssl_client_escaped_cert variable.

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
	->has_daemon('openssl')->plan(3);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;
    ssl_verify_client optional_no_ca;

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        location /cert {
            return 200 $ssl_client_raw_cert;
        }
        location /escaped {
            return 200 $ssl_client_escaped_cert;
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

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

my ($cert) = cert('/cert') =~ /\x0d\x0a?\x0d\x0a?(.*)/ms;
my ($escaped) = cert('/escaped') =~ /\x0d\x0a?\x0d\x0a?(.*)/ms;

ok($cert, 'ssl_client_raw_cert');
ok($escaped, 'ssl_client_escaped_cert');

$escaped =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
is($escaped, $cert, 'ssl_client_escaped_cert unescape match');

###############################################################################

sub cert {
	my ($uri) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => port(8443),
			SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
			SSL_cert_file => "$d/localhost.crt",
			SSL_key_file => "$d/localhost.key",
			SSL_error_trap => sub { die $_[1] },
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	http_get($uri, socket => $s);
}

###############################################################################
