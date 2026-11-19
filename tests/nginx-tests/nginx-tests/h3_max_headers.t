#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for max headers limit in requests.

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
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

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

        max_headers 5;

        location / { }
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
$t->try_run('no max_headers')->plan(2);

###############################################################################

is(get('/', 5), '200', 'max headers');
is(get('/', 6), '400', 'max headers reached');

###############################################################################

sub get {
	my ($uri, $count) = @_;

	my $h = [
		{ name => ':method', value => 'GET', mode => 0 },
		{ name => ':scheme', value => 'http', mode => 0 },
		{ name => ':path', value => '/', mode => 0 },
		{ name => ':authority', value => 'localhost', mode => 2 }];

	push @$h, map {{ name => 'x-blah', value => $_, mode => 4 }}
		1 .. $count;

	my $s = Test::Nginx::HTTP3->new();
	my $sid = $s->new_stream({ headers => $h });
	my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

	my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
	return $frame->{headers}->{':status'};
}

###############################################################################
