#!/usr/bin/perl

# Copyright (C) 2019 Alibaba Group Holding Limited

# DTLS test.

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

my $t = Test::Nginx->new()->has(qw/stream_ssl/)->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    server {
        listen 127.0.0.1:%%PORT_8980_UDP%% reuseport ssl udp;
        ssl_protocols dtlsv1;
        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        return "ok"; 
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
my $ret1 = `openssl s_client -connect 127.0.0.1:8980 -dtls1 | grep "ok"`;

like($ret1, qr/ok/, 'https success');
$t->stop();
