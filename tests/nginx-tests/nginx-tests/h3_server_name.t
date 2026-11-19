#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol, SNI TLS extension and regex in server_name.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP2;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has(qw/http http_ssl http_v2 http_v3 rewrite socket_ssl_alpn cryptx/)
	->has_daemon('openssl')->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    http2 on;

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  ~^(?P<name>.+)\.example\.com$;

        location / {
            return 200 $name;
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

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->run();

###############################################################################

# ssl_servername_regex wasn't inherited from QUIC connection,
# other protocols are provided for convenience

is(get1('test.example.com'), 'test', 'http1 - sni match');
is(get1('test.example.com', 'localhost'), 'test', 'http1 - sni not found');

is(get2('test.example.com'), 'test', 'http2 - sni match');
is(get2('test.example.com', 'localhost'), 'test', 'http2 - sni not found');

is(get3('test.example.com'), 'test', 'http3 - sni match');
is(get3('test.example.com', 'localhost'), 'test', 'http3 - sni not found');

###############################################################################

sub get1 {
	my ($host, $sni) = @_;
	http("GET / HTTP/1.0\nHost: $host\n\n",
		SSL => 1,
		SSL_hostname => $sni || $host,
		SSL_alpn_protocols => ['http/1.1'])
			=~ /.*?\x0d\x0a?\x0d\x0a?(.*)/ms;
	return $1;
}

sub get2 {
	my ($host, $sni) = @_;
	my $sock = http('', start => 1,
		SSL => 1,
		SSL_hostname => $sni || $host,
		SSL_alpn_protocols => ['h2']);
	my $s = Test::Nginx::HTTP2->new(undef, socket => $sock);
	my $sid = $s->new_stream({ host => $host });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{data};
}

sub get3 {
	my ($host, $sni) = @_;
	my $s = Test::Nginx::HTTP3->new(8980, sni => $sni || $host);
	my $sid = $s->new_stream({ host => $host });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "DATA" } @$frames;
	return $frame->{data};
}

###############################################################################
