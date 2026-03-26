#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Valentin Bartenev
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol, TLS SNI extension.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 rewrite cryptx/)
	->has_daemon('openssl')->plan(10)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            return 200 $server_name:$ssl_server_name;
        }

        location /name {
            return 200 $ssl_session_reused:$ssl_server_name;
        }
    }

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  example.com;

        ssl_certificate_key example.com.key;
        ssl_certificate example.com.crt;

        location / {
            return 200 $server_name:$ssl_server_name;
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

foreach my $name ('localhost', 'example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

like(get_cert_cn(), qr!localhost!, 'default cert');
like(get_cert_cn('example.com'), qr!example.com!, 'sni cert');

ok(get_tp(), 'default transport params');
ok(get_tp('example.com'), 'sni transport params');

like(get_host('example.com'), qr!example.com:example.com!,
	'host exists, sni exists, and host is equal sni');

like(get_host('example.com', 'example.org'), qr!example.com:example.org!,
	'host exists, sni not found');

TODO: {
local $TODO = 'sni restrictions';

like(get_host('example.com', 'localhost'), qr!400 Bad Request!,
	'host exists, sni exists, and host is not equal sni');

like(get_host('example.org', 'example.com'), qr!400 Bad Request!,
	'host not found, sni exists');

}

# $ssl_server_name in sessions

my $psk;
my $ctx = \$psk;

like(get('/name', 'localhost', $ctx), qr/^\.:localhost$/m, 'ssl server name');

TODO: {
local $TODO = 'no TLSv1.3 sessions in LibreSSL'
	if $t->has_module('LibreSSL');

like(get('/name', 'localhost', $ctx), qr/^r:localhost$/m,
	'ssl server name - reused');

}

###############################################################################

sub get_cert_cn {
	my ($host) = @_;
	my $s = Test::Nginx::HTTP3->new(8980, sni => $host);
	return $s->{tlsm}{cert};
}

sub get_tp {
	my ($host) = @_;
	my $s = Test::Nginx::HTTP3->new(8980, sni => $host);
	return $s->{tp};
}

sub get_host {
	my ($host, $sni) = @_;

	my $s = Test::Nginx::HTTP3->new(8980, sni => $sni || $host);
	my $sid = $s->new_stream({ host => $host });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{data};
}

sub get {
	my ($uri, $host, $ctx) = @_;

	my $s = Test::Nginx::HTTP3->new(8980, sni => $host, psk_list => $$ctx);
	my $sid = $s->new_stream({ host => $host, path => $uri });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
	$$ctx = $s->{psk_list};

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{data};
}

###############################################################################
