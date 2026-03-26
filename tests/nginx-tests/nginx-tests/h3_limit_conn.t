#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with limit_conn.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 limit_conn proxy cryptx/)
	->has_daemon('openssl')->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    limit_conn_zone  $binary_remote_addr  zone=conn:1m;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            limit_conn conn 1;
            proxy_pass http://127.0.0.1:8080/stub;
        }

        location /stub {
            limit_rate 200;
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

$t->write_file('stub', 'x' x 200);
$t->run();

###############################################################################

my $s = Test::Nginx::HTTP3->new();
my $sid = $s->new_stream();
my $sid2 = $s->new_stream();
my $frames = $s->read(all => [
	{ sid => $sid, fin => 1 },
	{ sid => $sid2, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid } @$frames;
is($frame->{headers}->{':status'}, 200, 'limit_conn first stream');

($frame) = grep { $_->{type} eq "HEADERS" && $_->{sid} == $sid2 } @$frames;
is($frame->{headers}->{':status'}, 503, 'limit_conn rejected');

###############################################################################
