#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for server_name selection.

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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(9)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server_names_hash_bucket_size 64;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Server $server_name;
            return 204;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  www.example.com;

        location / {
            add_header X-Server $server_name;
            return 204;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^EXAMPLE\.COM$;

        location / {
            add_header X-Server $server_name;
            return 204;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^(?P<name>.+)\Q.example.com\E$;

        location / {
            add_header X-Server $server_name;
            add_header X-Match  $name;
            return 204;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  "~^(?P<name>www\p{N}+)\.example\.com$";

        location / {
            add_header X-Server $server_name;
            add_header X-Match  $name;
            return 204;
        }
    }
}

EOF

$t->run();

###############################################################################

sub http_server($) {
	my ($host) = @_;
	return http(<<EOF);
GET / HTTP/1.0
Host: $host

EOF
}

###############################################################################

like(http_server('xxx'), qr/X-Server: localhost/, 'default');

like(http_server('www.example.com'), qr/\QX-Server: www.example.com/,
	'www.example.com');
like(http_server('WWW.EXAMPLE.COM'), qr/\QX-Server: www.example.com/,
	'www.example.com uppercase');

like(http_server('example.com'), qr/\QX-Server: ~^EXAMPLE\.COM$/,
	'example.com regex');
like(http_server('EXAMPLE.COM'), qr/\QX-Server: ~^EXAMPLE\.COM$/,
	'example.com regex uppercase');

like(http_server('blah.example.com'), qr/X-Match: blah/,
	'(P<name>.*).example.com named capture');
like(http_server('BLAH.EXAMPLE.COM'), qr/X-Match: blah/,
	'(P<name>.*).example.com named capture uppercase');

like(http_server('www01.example.com'), qr/X-Match: www01/,
	'\p{N} in named capture');
like(http_server('WWW01.EXAMPLE.COM'), qr/X-Match: www01/,
	'\p{N} in named capture uppercase');

###############################################################################
