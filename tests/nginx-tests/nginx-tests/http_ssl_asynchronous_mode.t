#!/usr/bin/perl

# (C) Intel, Inc.

# Tests for http ssl asynchronous mode.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl/)
    ->has_daemon('openssl');

$t->plan(2)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

user root;

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_buffer_size 64k;
    ssl_async on;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            index index.html index.htm;
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
        . "-config '$d/openssl.conf' -subj '/CN=$name/' "
        . "-out '$d/$name.crt' -keyout '$d/$name.key' "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for $name: $!\n";
}

$t->write_file('index.html', <<EOF);
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
EOF

$t->run();
sleep 10;

my $COUNT_RSA = '0';
my $COUNT_ECDHE_RSA = '0';
my $aes = get_file_aes128_sha($t->testdir());

ok( $aes == $COUNT_RSA,'Test AES128-SHA!
    **Note**: Please make sure build Nginx using "--with-debug --with-openssl-async" and set COUNT_RSA 2 if you want see the result of async mode');
sleep 5;

my $ecdhe_rsa = get_file_ecdhe_rsa_aes128_sha($t->testdir());
ok( $ecdhe_rsa == $COUNT_ECDHE_RSA,'Test ECDHE-RSA-AES128-SHA!
    **Note**: Please make sure build Nginx using "--with-debug" and "--with-openssl-async" and set COUNT_ECDHE_RSA 2 if you want see the result of async mode');

$t->stop();
################################################################################

sub get_file_aes128_sha {
    my ($nginx) = @_;
    system('echo "GET /index.html" | openssl s_client -connect localhost:8080 '
        .'-cipher AES128-SHA -ign_eof') == 0
        or die "Can't get the index.html via the cipher AES128-SHA\n";
    my $result=0;
    $result=`grep -c 'SSL ASYNC WANT' $nginx/error.log`;
    return $result;
}

sub get_file_ecdhe_rsa_aes128_sha {
    my ($nginx) = @_;
    my $openssl_version=`openssl version|cut -d" " -f2`;
    $openssl_version ge "1.0.1" or die "Openssl version too low\n";

    `echo " " >$nginx/error.log`;
    system('echo "GET /index.html" | openssl s_client -connect localhost:8080 '
        .'-cipher ECDHE-RSA-AES128-SHA -ign_eof') == 0
        or die "Can't get the index.html via the cipher ECDHE-RSA-AES128-SHA\n";
    my $result=0;
    $result=`grep -c 'SSL ASYNC WANT' $nginx/error.log`;
    return $result;
}

###############################################################################
