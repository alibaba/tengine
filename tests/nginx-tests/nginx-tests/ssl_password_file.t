#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for ssl_password_file directive.

###############################################################################

use warnings;
use strict;

use Test::More;

use POSIX qw/ mkfifo /;
use Socket qw/ $CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http http_ssl rewrite socket_ssl/)
	->has_daemon('openssl');

$t->plan(3)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    # inherited by server "inherits"
    ssl_password_file password_http;

    server {
        listen       127.0.0.1:8443 ssl;
        listen       127.0.0.1:8080;
        server_name  localhost;

        ssl_password_file password;

        location / {
            return 200 "$scheme";
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  two_entries;

        ssl_password_file password_many;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  file_is_fifo;

        ssl_password_file password_fifo;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  inherits;

        ssl_certificate_key inherits.key;
        ssl_certificate inherits.crt;
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
mkfifo("$d/password_fifo", 0700);

foreach my $name ('localhost', 'inherits') {
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

$t->write_file('password', 'localhost');
$t->write_file('password_many', "wrong$CRLF" . "localhost$CRLF");
$t->write_file('password_http', 'inherits');

my $p = fork();
exec("echo localhost > $d/password_fifo") if $p == 0;

# do not mangle with try_run()
# we need to distinguish ssl_password_file support vs its brokenness

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
kill 'INT', $p if $@;

###############################################################################

is($@, '', 'ssl_password_file works');

# simple tests to ensure that nothing broke with ssl_password_file directive

like(http_get('/'), qr/200 OK.*http/ms, 'http');
like(http_get('/', SSL => 1), qr/200 OK.*https/ms, 'https');

###############################################################################
