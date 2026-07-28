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
        server_name  ~^(?P<name>[a-z]+)\Q.example.com\E$;

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

is(get_server('xxx'), 'localhost', 'default');
is(get_server(), undef, 'empty');

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
	get(@_) =~ /X-Server: (.+)\x0d/m;
	return $1;
}

sub get_match {
	get(@_) =~ /X-Match: (.+)\x0d/m;
	return $1;
}

sub get {
	my ($host) = @_;

	my $str = 'GET / HTTP/1.0' . CRLF .
		(defined $host ? "Host: $host" . CRLF : '') .
		CRLF;

	return http($str);
}

###############################################################################
