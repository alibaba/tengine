#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream proxy module with variables in ssl certificates.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl stream_map http http_ssl/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    map $server_port $cert {
        %%PORT_8082%% 1;
        %%PORT_8083%% 2;
        %%PORT_8084%% 3;
        %%PORT_8086%% 3;
        %%PORT_8085%% "";
    }

    proxy_ssl on;
    proxy_ssl_session_reuse off;

    proxy_ssl_certificate $cert.example.com.crt;
    proxy_ssl_certificate_key $cert.example.com.key;
    proxy_ssl_password_file password;

    server {
        listen      127.0.0.1:8082;
        listen      127.0.0.1:8083;
        proxy_pass  127.0.0.1:8080;
    }

    server {
        listen      127.0.0.1:8084;
        proxy_pass  127.0.0.1:8081;

        proxy_ssl_certificate $cert.example.com.crt;
        proxy_ssl_certificate_key $cert.example.com.key;
        proxy_ssl_password_file password;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  127.0.0.1:8081;
    }

    server {
        listen      127.0.0.1:8085;
        proxy_pass  127.0.0.1:8081;

        proxy_ssl_certificate $cert;
        proxy_ssl_certificate_key $cert;
    }
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        ssl_certificate 2.example.com.crt;
        ssl_certificate_key 2.example.com.key;

        ssl_verify_client optional_no_ca;
        ssl_trusted_certificate 1.example.com.crt;

        location / {
            add_header X-Verify $ssl_client_verify;
            add_header X-Name   $ssl_client_s_dn;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  localhost;

        ssl_certificate 1.example.com.crt;
        ssl_certificate_key 1.example.com.key;

        ssl_verify_client optional_no_ca;
        ssl_trusted_certificate 3.example.com.crt;

        location / {
            add_header X-Verify $ssl_client_verify;
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

foreach my $name ('1.example.com', '2.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

foreach my $name ('3.example.com') {
	system("openssl genrsa -out $d/$name.key -passout pass:$name "
		. "-aes128 2048 >>$d/openssl.out 2>&1") == 0
		or die "Can't create private key: $!\n";
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt "
		. "-key $d/$name.key -passin pass:$name"
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

sleep 1 if $^O eq 'MSWin32';

$t->write_file('password', '3.example.com');
$t->write_file('index.html', '');

$t->run()->plan(5);

###############################################################################

like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8082))),
	qr/X-Verify: SUCCESS/ms, 'variable - verify certificate');
like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8083))),
	qr/X-Verify: FAILED/ms, 'variable - fail certificate');
like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8084))),
	qr/X-Verify: SUCCESS/ms, 'variable - with encrypted key');

TODO: {
todo_skip 'leaves coredump', 1 unless $t->has_version('1.27.5')
	or $ENV{TEST_NGINX_UNSAFE};

like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8086))),
	qr/X-Verify: SUCCESS/ms, 'variable - with encrypted key optimized');

}

like(http_get('/', socket => IO::Socket::INET->new('127.0.0.1:' . port(8085))),
	qr/X-Verify: NONE/ms, 'variable - no certificate');

###############################################################################
