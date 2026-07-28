#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for proxy to ssl backend, proxy_ssl_certificate_cache directive.

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

my $t = Test::Nginx->new()
	->has(qw/http http_ssl proxy openssl:1.0.2/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_ssl_session_reuse off;
        proxy_ssl_certificate $arg_cert.example.com.crt;
        proxy_ssl_certificate_key $arg_cert.example.com.key;

        proxy_ssl_certificate_cache max=4 valid=2s;

        location / {
            proxy_pass https://127.0.0.1:8081/;
        }

        location /enc {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_password_file password;
        }

        location /nocache {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_certificate_cache off;
        }

        location /inactive {
            proxy_pass https://127.0.0.1:8081/;
            proxy_ssl_certificate_cache max=4 inactive=1s;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate localhost.crt;
        ssl_certificate_key localhost.key;

        ssl_verify_client optional_no_ca;
        ssl_trusted_certificate root.crt;

        location / {
            add_header X-Name $ssl_client_s_dn;
        }
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

[ myca_policy ]
commonName = supplied
EOF

foreach my $name ('root', 'localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('certserial', '1000');
$t->write_file('certindex', '');

foreach my $name ('1.example.com', '2.example.com', '3.example.com',
	'4.example.com', '5.example.com', 'dummy')
{
	system('openssl req -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
	system("openssl ca -batch -config $d/ca.conf "
		. "-keyfile $d/root.key -cert $d/root.crt "
		. "-subj /CN=$name/ -in $d/$name.csr -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't sign certificate for $name: $!\n";
}

foreach my $name ('e.example.com') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.csr "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
	system("openssl ca -batch -config $d/ca.conf "
		. "-keyfile $d/root.key -cert $d/root.crt "
		. "-subj /CN=$name/ -in $d/$name.csr -out $d/$name.crt "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't sign certificate for $name: $!\n";
}

update($t, '4b.example.com', '4.example.com');
update($t, 'eb.example.com', 'e.example.com');

$t->write_file('password', 'e.example.com');
$t->write_file('index.html', '');

$t->try_run('no proxy_ssl_certificate_cache')->plan(20);

###############################################################################

like(http_get('/?cert=1'), qr/CN=1.example.com/, 'certificate 1');

update($t, '1.example.com');
like(http_get('/?cert=1'), qr/CN=1.example.com/, 'certificate 1 cached');

like(http_get('/?cert=2'), qr/CN=2.example.com/, 'certificate 2');
like(http_get('/?cert=3'), qr/CN=3.example.com/, 'certificate 3');

# eviction after inserting 4 new items

like(http_get('/?cert=1'), qr/500 Internal/, 'certificate 1 evicted');

update($t, '2.example.com', 'dummy');
update($t, '3.example.com');

# replaced or removed certificates do not affect caching

like(http_get('/?cert=2'), qr/CN=2.example.com/, 'certificate 2 cached');
like(http_get('/?cert=3'), qr/CN=3.example.com/, 'certificate 3 cached');

# encrypted certificates are exempt from caching

like(http_get('/enc/?cert=e'), qr/CN=e.example.com/, 'encrypted');

like(http_get('/?cert=e'), qr/500 Internal/, 'encrypted no password');

update($t, 'e.example.com', 'dummy');
like(http_get('/enc/?cert=e'), qr/CN=dummy/, 'encrypted not cached');

# replacing non-cacheable item with cacheable doesn't affect cacheability

update($t, 'e.example.com', 'eb.example.com');
like(http_get('/enc/?cert=e'), qr/CN=dummy/, 'cached after encrypted');

like(http_get('/nocache/?cert=4'), qr/CN=4.example.com/, 'no cache');

update($t, '4.example.com', 'dummy');
like(http_get('/nocache/?cert=4'), qr/CN=dummy/, 'no cache updated');

like(http_get('/inactive/?cert=5'), qr/CN=5.example.com/, 'inactive');

select undef, undef, undef, 3.1;

like(http_get('/?cert=2'), qr/CN=dummy/, 'certificate 2 expired');
like(http_get('/?cert=3'), qr/500 Internal/, 'certificate 3 expired');

# replacing cacheable item with non-cacheable doesn't affect cacheability

like(http_get('/enc/?cert=e'), qr/CN=e.example.com/, 'encrypted after cached');

update($t, 'e.example.com', 'dummy');
like(http_get('/enc/?cert=e'), qr/CN=dummy/,
	'encrypted not cached after cached');

# eviction after inactive time

update($t, '5.example.com', 'dummy');

like(http_get('/inactive/?cert=4b'), qr/CN=4.example.com/, 'inactive expire');
like(http_get('/inactive/?cert=5'), qr/CN=dummy/, 'inactive expired');

###############################################################################

sub update {
	my ($t, $old, $new) = @_;

	for my $ext ("crt", "key") {
		if (defined $new) {
			$t->write_file("$old.$ext.tmp",
				$t->read_file("$new.$ext"));
			rename("$d/$old.$ext.tmp", "$d/$old.$ext");

		} else {
			unlink "$d/$old.$ext";
		}
	}
}

###############################################################################
