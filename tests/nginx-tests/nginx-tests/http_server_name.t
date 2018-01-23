#!/usr/bin/perl

# (C) Maxim Dounin
# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for server_name selection.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

plan(skip_all => 'win32') if $^O eq 'MSWin32';

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(20)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

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
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  "";

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  www.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^EXAMPLE\.COM$;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  ~^(?P<name>.+)\Q.example.com\E$;

        location / {
            add_header X-Server $server_name;
            add_header X-Match  $name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  "~^(?P<name>www\p{N}+)\.example\.com$";

        location / {
            add_header X-Server $server_name;
            add_header X-Match  $name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  many.example.com many2.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  many3.example.com;
        server_name  many4.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  *.wc.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  *.pref.wc.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  wc2.example.*;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  wc2.example.com.*;

        location / {
            add_header X-Server $server_name;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  .dot.example.com;

        location / {
            add_header X-Server $server_name;
        }
    }
}

EOF

$t->write_file('index.html', '');
$t->run();

###############################################################################

like(http_server('xxx'), qr/X-Server: localhost/, 'default');
unlike(http_server(), qr/X-Server/, 'empty');

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

like(http_server('many.example.com'), qr/\QX-Server: many.example.com/,
	'name row - first');
like(http_server('many2.example.com'), qr/\QX-Server: many.example.com/,
	'name row - second');

like(http_server('many3.example.com'), qr/\QX-Server: many3.example.com/,
	'name list - first');
like(http_server('many4.example.com'), qr/\QX-Server: many3.example.com/,
	'name list - second');

like(http_server('www.wc.example.com'),
	qr/\QX-Server: *.wc.example.com/, 'wildcard first');
like(http_server('www.pref.wc.example.com'),
	qr/\QX-Server: *.pref.wc.example.com/, 'wildcard first most specific');
like(http_server('wc2.example.net'),
	qr/\QX-Server: wc2.example.*/, 'wildcard last');
like(http_server('wc2.example.com.pref'),
	qr/\QX-Server: wc2.example.com.*/, 'wildcard last most specific');

like(http_server('www.dot.example.com'), qr/\QX-Server: dot.example.com/,
	'wildcard dot');
like(http_server('dot.example.com'), qr/\QX-Server: dot.example.com/,
	'wildcard dot empty');

###############################################################################

sub http_server {
	my ($host) = @_;

	my $str = 'GET / HTTP/1.0' . CRLF .
		(defined $host ? "Host: $host" . CRLF : '') .
		CRLF;

	return http($str);
}

###############################################################################
