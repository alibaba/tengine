#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol, ssl_reject_handshake.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 cryptx/)
	->has_daemon('openssl')->plan(7)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    add_header X-Name $ssl_server_name;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        ssl_reject_handshake on;
    }

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  virtual;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
    }

    server {
        listen       127.0.0.1:%%PORT_8982_UDP%% quic;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;
    }

    server {
        listen       127.0.0.1:%%PORT_8982_UDP%% quic;
        server_name  virtual1;
    }

    server {
        listen       127.0.0.1:%%PORT_8982_UDP%% quic;
        server_name  virtual2;

        ssl_reject_handshake on;
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

$t->write_file('index.html', '');

$t->run();

###############################################################################

my $alert = 0x100 + 112; # "unrecognized_name"

SKIP: {
# OpenSSL < 1.1.1j requires TLSv1.3-capable certificates in the default server
# See commit "Modify is_tls13_capable() to take account of the servername cb"
# Additionally, it was seen with OpenSSL 1.1.1k FIPS as found on RHEL 8.1

my $got = bad('default', 8980);
skip "OpenSSL too old", 3 if $got && $got == 0x100 + 70; # "protocol_version"

# default virtual server rejected

TODO: {
local $TODO = 'broken send_alert in LibreSSL'
	if $t->has_module('LibreSSL')
	and not $t->has_feature('libressl:4.0.0');

is(bad('default', 8980), $alert, 'default rejected');
is(bad(undef, 8980), $alert, 'absent sni rejected');

}

like(get('virtual', 8980), qr/virtual/, 'virtual accepted');

}

# non-default server "virtual2" rejected

like(get('default', 8982), qr/default/, 'default accepted');
like(get(undef, 8982), qr/200/, 'absent sni accepted');
like(get('virtual1', 8982), qr/virtual1/, 'virtual 1 accepted');

TODO: {
local $TODO = 'broken send_alert in LibreSSL'
	if $t->has_module('LibreSSL')
	and not $t->has_feature('libressl:4.0.0');

is(bad('virtual2', 8982), $alert, 'virtual 2 rejected');

}

###############################################################################

sub get {
	my ($sni, $port) = @_;
	my $s = Test::Nginx::HTTP3->new($port, sni => $sni);
	my $sid = $s->new_stream({ host => $sni });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{':status'}
		. ($frame->{headers}->{'x-name'} || '');
}

sub bad {
	my ($sni, $port) = @_;
	my $s = Test::Nginx::HTTP3->new($port, sni => $sni, probe => 1);
	my $frames = $s->read(all => [{ type => "CONNECTION_CLOSE" }]);

	my ($frame) = grep { $_->{type} eq "CONNECTION_CLOSE" } @$frames;
	return $frame->{error};
}

###############################################################################
