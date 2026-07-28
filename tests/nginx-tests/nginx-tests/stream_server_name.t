#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Andrey Zelenkov
# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for server_name selection.

###############################################################################

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

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http rewrite/)
	->has(qw/stream stream_ssl stream_return sni socket_ssl_sni/)
	->has_daemon('openssl')->plan(19)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server_names_hash_bucket_size 64;

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  localhost;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  www.example.com;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^EXAMPLE\.COM$;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^(?P<name>[a-z]+)\Q.example.com\E$;

        return $name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  "~^(?P<name>www\p{N}+)\.example\.com$";

        return $name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  many.example.com many2.example.com;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  many3.example.com;
        server_name  many4.example.com;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  *.wc.example.com;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  *.pref.wc.example.com;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  wc2.example.*;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  wc2.example.com.*;

        return $server_name;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  .dot.example.com;

        return $server_name;
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

$t->run();

###############################################################################

is(get_server('xxx'), 'localhost', 'default');

is(get_server('www.example.com'), 'www.example.com',
	'www.example.com');
is(get_server('WWW.EXAMPLE.COM'), 'www.example.com',
	'www.example.com uppercase');

is(get_server('example.com'), '~^EXAMPLE\.COM$',
	'example.com regex');
is(get_server('EXAMPLE.COM'), '~^EXAMPLE\.COM$',
	'example.com regex uppercase');

is(get_match('blah.example.com'), 'blah',
	'(P<name>.*).example.com named capture');
is(get_match('BLAH.EXAMPLE.COM'), 'blah',
	'(P<name>.*).example.com named capture uppercase');

is(get_match('www01.example.com'), 'www01',
	'\p{N} in named capture');
is(get_match('WWW01.EXAMPLE.COM'), 'www01',
	'\p{N} in named capture uppercase');

is(get_server('many.example.com'), 'many.example.com',
	'name row - first');
is(get_server('many2.example.com'), 'many.example.com',
	'name row - second');

is(get_server('many3.example.com'), 'many3.example.com',
	'name list - first');
is(get_server('many4.example.com'), 'many3.example.com',
	'name list - second');

is(get_server('www.wc.example.com'),
	'*.wc.example.com', 'wildcard first');
is(get_server('www.pref.wc.example.com'),
	'*.pref.wc.example.com', 'wildcard first most specific');
is(get_server('wc2.example.net'),
	'wc2.example.*', 'wildcard last');
is(get_server('wc2.example.com.pref'),
	'wc2.example.com.*', 'wildcard last most specific');

is(get_server('www.dot.example.com'), 'dot.example.com',
	'wildcard dot');
is(get_server('dot.example.com'), 'dot.example.com',
	'wildcard dot empty');

###############################################################################

sub get_server {
	my ($host) = @_;

	my $s = stream(
		PeerAddr => '127.0.0.1:' . port(8080),
		SSL => 1,
		SSL_hostname => $host
	);

	log_in("ssl sni: $host") if defined $host;

	return $s->read();
}

sub get_match {
	&get_server;
}

###############################################################################
