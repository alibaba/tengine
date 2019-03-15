#!/usr/bin/perl

# Copyright (C) 2019 Alibaba Group Holding Limited

# Stream tests for SNI.

###############################################################################
# "For using stream_sni.t, you should configure Tengine by using --with-stream_ssl_module --with-stream_sni";
use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_return stream_sni/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

worker_processes 1;  # NOTE: The default value of Tengine worker_processes directive is `worker_processes auto;`.

stream {
    proxy_ssl on;
    proxy_ssl_session_reuse on;
    proxy_connect_timeout 2s;

    server {
        listen      127.0.0.1:8081 ssl;
        server_name www.test1.com;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        return "www.test1.com"; 
    }

    server {
        listen      127.0.0.1:8081 ssl;
        server_name www.test2.com;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        return "www.test2.com";
    }

    server {
        listen      127.0.0.1:8081 ssl default;
        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        return "default";
    }

    server {
        listen      127.0.0.1:8082 ssl;
        server_name www.testsniforce.com;
        ssl_sni_force on;
        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;
        return "www.testsniforce.com";
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
my $ret1 = `openssl s_client -connect localhost:8081 -quiet -servername "www.test1.com"| grep "test1"`;
my $ret2 = `openssl s_client -connect localhost:8081 -quiet -servername "www.test2.com" | grep "test2"`;
my $ret3 = `openssl s_client -connect localhost:8081 -quiet -servername "www.test3.com"| grep "default"`;
my $ret4 = `openssl s_client -connect localhost:8082 -quiet -servername "www.testsniforce.com"| grep "force"`;
my $ret5 = `openssl s_client -connect localhost:8082 -quiet -servername "www.testother.com"| grep "force"`;

like($ret1, qr/www.test1.com/, 'Match www.test1.com success');
like($ret2, qr/www.test2.com/, 'Match www.test2.com success');
like($ret3, qr/default/, 'Match default success');
like($ret4, qr/www.testsniforce.com/, 'sni force success');
unlike($ret5, qr/www.testsniforce.com/, 'reject unknown domain success');
$t->stop();
