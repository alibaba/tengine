#!/usr/bin/perl

# Copyright (C) 2019 Alibaba Group Holding Limited.

# Tests for stream ssl handshake time.

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
    require IO::Socket::SSL;
};

my $t = Test::Nginx->new()->has(qw/stream stream_ssl/)
    ->has_daemon('openssl');

$t->plan(2)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    #log_format status '-';
    log_format status '$ssl_handshakd_time';
    access_log  %%TESTDIR%%/time.log status;
    server {
        listen       127.0.0.1:8080 ssl;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        return "ok";
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
        . "-config '$d/openssl.conf' -subj '/CN=$name/' "
        . "-out '$d/$name.crt' -keyout '$d/$name.key' "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for $name: $!\n";
}

$t->run();
my $testret=`echo "GET" | openssl s_client -connect 127.0.0.1:8080 -ign_eof`;
$t->stop();
my $logfile = $t->read_file('time.log');

like($testret, qr/ok/,'acccess ok');
unlike($logfile, qr/-/,'time ok');
