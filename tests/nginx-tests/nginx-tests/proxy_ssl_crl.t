#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy to ssl backend, backend certificate verification with CRL.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy/)
	->has_daemon('openssl')->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_ssl_verify on;
    proxy_ssl_trusted_certificate int-root.crt;
    proxy_ssl_session_reuse off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /1 {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_trusted_certificate root.crt;
            proxy_ssl_name int;
            proxy_ssl_crl empty.crl;
        }

        location /2 {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_trusted_certificate root.crt;
            proxy_ssl_name int;
            proxy_ssl_crl root.crl;
        }

        location /3 {
            proxy_pass https://127.0.0.1:8082/;
            proxy_ssl_verify_depth 2;
            proxy_ssl_name end;
            proxy_ssl_crl root.crl;
        }

        location /4 {
            proxy_pass https://127.0.0.1:8082/;
            proxy_ssl_verify_depth 2;
            proxy_ssl_name end;
            proxy_ssl_crl empty.crl;
        }

        location /5 {
            proxy_pass https://127.0.0.1:8082/;
            proxy_ssl_verify_depth 2;
            proxy_ssl_name end;
            proxy_ssl_crl empty-chain.crl;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate int.crt;
        ssl_certificate_key int.key;
    }

    server {
        listen       127.0.0.1:8082 ssl;
        server_name  localhost;

        ssl_certificate end.crt;
        ssl_certificate_key end.key;
    }
}

EOF

my $d = $t->testdir();

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
x509_extensions = myca_extensions
[ req_distinguished_name ]
[ myca_extensions ]
basicConstraints = critical,CA:TRUE
EOF

$t->write_file('ca.conf', <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d
database = $d/certindex
default_md = sha256
policy = myca_policy
serial = $d/certserial
default_days = 1
x509_extensions = myca_extensions

[ myca_policy ]
commonName = supplied

[ myca_extensions ]
basicConstraints = critical,CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

foreach my $name ('root') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('int', 'end') {
	system("openssl req -new "
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-subj /CN=int/ -in $d/int.csr -out $d/int.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for int: $!\n";

system("openssl ca -batch -config $d/ca.conf "
	. "-keyfile $d/int.key -cert $d/int.crt "
	. "-subj /CN=end/ -in $d/end.csr -out $d/end.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't sign certificate for end: $!\n";

system("openssl ca -gencrl -config $d/ca.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-out $d/empty.crl -crldays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't create empty crl: $!\n";

system("openssl ca -gencrl -config $d/ca.conf "
	. "-keyfile $d/int.key -cert $d/int.crt "
	. "-out $d/int.crl -crldays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't update crl: $!\n";

$t->write_file('empty-chain.crl',
	$t->read_file('empty.crl') . $t->read_file('int.crl'));

system("openssl ca -config $d/ca.conf -revoke $d/int.crt "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't revoke int.crt: $!\n";

system("openssl ca -gencrl -config $d/ca.conf "
	. "-keyfile $d/root.key -cert $d/root.crt "
	. "-out $d/root.crl -crldays 1 "
	. ">>$d/openssl.out 2>&1") == 0
	or die "Can't update crl: $!\n";

$t->write_file('int-root.crt',
	$t->read_file('int.crt') . $t->read_file('root.crt'));

$t->write_file('index.html', '');
$t->run();

###############################################################################

like(http_get('/1'), qr/200/, 'proxy crl - no revoked certs');
like(http_get('/2'), qr/502 Bad/, 'proxy crl - client revoked');
like(http_get('/3'), qr/502 Bad/, 'proxy crl - CA revoked');

# intermediate CAs, incomplete chain

like(http_get('/4'), qr/502 Bad/, 'proxy crl - incomplete chain');
like(http_get('/5'), qr/200/, 'proxy crl - no revoked chain');

###############################################################################
