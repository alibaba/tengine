#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy module, proxy_max_temp_file_size directive.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy cryptx/)
	->has_daemon('openssl')->plan(4);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        server_name  localhost;

        proxy_buffer_size 4k;
        proxy_buffers 8 4k;

        location / {
            proxy_max_temp_file_size 4k;
            proxy_pass http://127.0.0.1:8081/;
        }

        location /off/ {
            proxy_max_temp_file_size 0;
            proxy_pass http://127.0.0.1:8081/;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

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

$t->write_file('1', 'X' x (1024 * 1024));
$t->run();

###############################################################################

# test that the response is wholly proxied when all event pipe buffers are full

my $s = Test::Nginx::HTTP3->new();
my $sid = $s->new_stream({ path => '/1' });

select undef, undef, undef, 0.4;
$s->h3_max_data(1024 * 1025, $sid);
$s->h3_max_data(1024 * 1025);

my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
my $body = join '', map { $_->{data} } grep { $_->{type} eq "DATA" } @$frames;
like($body, qr/^X+$/m, 'no pipe bufs - body');
is(length($body), 1024 * 1024, 'no pipe bufs - body length');

# also with disabled proxy temp file

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/off/1' });

select undef, undef, undef, 0.4;
$s->h3_max_data(1024 * 1025, $sid);
$s->h3_max_data(1024 * 1025);

$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);
$body = join '', map { $_->{data} } grep { $_->{type} eq "DATA" } @$frames;
like($body, qr/^X+$/m, 'no temp file - body');
is(length($body), 1024 * 1024, 'no temp file - body length');

###############################################################################
