#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream to ssl backend, proxy_ssl_certificate_cache directive.

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
	->has(qw/stream stream_ssl http http_ssl openssl:1.0.2 socket_ssl_sni/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    ssl_certificate localhost.crt;
    ssl_certificate_key localhost.key;

    proxy_ssl   on;
    proxy_ssl_session_reuse off;
    proxy_ssl_certificate $ssl_server_name.crt;
    proxy_ssl_certificate_key $ssl_server_name.key;

    proxy_ssl_certificate_cache max=4 valid=1s;

    # the server block is intentionally misplaced as a workaround for
    # password support optimization bug, introduced in d791b4aab (1.23.1)

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  5.example.com;

        proxy_pass  127.0.0.1:8081;
        proxy_ssl_certificate_cache max=4 inactive=1s;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        proxy_pass  127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  e.example.com;

        proxy_pass  127.0.0.1:8081;
        proxy_ssl_password_file password;
    }

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  4.example.com;

        proxy_pass  127.0.0.1:8081;
        proxy_ssl_certificate_cache off;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

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

like(get('1.example.com'), qr/CN=1.example.com/, 'certificate 1');

update($t, '1.example.com');
like(get('1.example.com'), qr/CN=1.example.com/, 'certificate 1 cached');

like(get('2.example.com'), qr/CN=2.example.com/, 'certificate 2');
like(get('3.example.com'), qr/CN=3.example.com/, 'certificate 3');

# eviction after inserting 4 new items

ok(!get('1.example.com'), 'certificate 1 evicted');

update($t, '2.example.com', 'dummy');
update($t, '3.example.com');

# replaced or removed certificates do not affect caching

like(get('2.example.com'), qr/CN=2.example.com/, 'certificate 2 cached');
like(get('3.example.com'), qr/CN=3.example.com/, 'certificate 3 cached');

# encrypted certificates are exempt from caching

like(get('e.example.com'), qr/CN=e.example.com/, 'encrypted');

ok(!get('e.example.com', 8444), 'encrypted no password');

update($t, 'e.example.com', 'dummy');
like(get('e.example.com'), qr/CN=dummy/, 'encrypted not cached');

# replacing non-cacheable item with cacheable doesn't affect cacheability

update($t, 'e.example.com', 'eb.example.com');
like(get('e.example.com'), qr/CN=dummy/, 'cached after encrypted');

like(get('4.example.com'), qr/CN=4.example.com/, 'no cache');

update($t, '4.example.com', 'dummy');
like(get('4.example.com'), qr/CN=dummy/, 'no cache updated');

like(get('5.example.com', 8444), qr/CN=5.example.com/, 'inactive');

select undef, undef, undef, 3.1;

like(get('2.example.com'), qr/CN=dummy/, 'certificate 2 expired');
ok(!get('3.example.com'), 'certificate 3 expired');

# replacing cacheable item with non-cacheable doesn't affect cacheability

like(get('e.example.com'), qr/CN=e.example.com/, 'encrypted after cached');

update($t, 'e.example.com', 'dummy');
like(get('e.example.com'), qr/CN=dummy/,
	'encrypted not cached after cached');

# eviction after inactive time

update($t, '5.example.com', 'dummy');

like(get('4b.example.com', 8444), qr/CN=4.example.com/, 'inactive expire');
like(get('5.example.com', 8444), qr/CN=dummy/, 'inactive expired');

###############################################################################

sub get {
	my ($host, $port) = @_;
	http_get('/',
		PeerAddr => '127.0.0.1:' . port($port || 8443),
		SSL => 1,
		SSL_hostname => $host);
}

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
