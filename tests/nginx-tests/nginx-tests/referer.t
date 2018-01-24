#!/usr/bin/perl

# (C) Sergey Kandaurov

# Tests for referer module.

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

my $t = Test::Nginx->new()->has(qw/http referer rewrite/)->plan(54);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  another;

        valid_referers server_names;
        return 200 "$host value $invalid_referer";
    }

    server {
        listen       127.0.0.1:8080;
        server_name  _;

        location / {
            valid_referers server_names;
            return 200 "$host value $invalid_referer";
        }
        server_name  below;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost ~bar ~^anchoredre$;

        location /blocked {
            valid_referers blocked www.example.org;
            return 200 "value $invalid_referer";
        }
        location /none {
            valid_referers none www.example.org;
            return 200 "value $invalid_referer";
        }
        location /simple {
            valid_referers www.example.org;
            return 200 "value $invalid_referer";
        }
        location /regex {
            valid_referers ~example.org ~(?-i)example.net;
            return 200 "value $invalid_referer";
        }
        location /regex2 {
            valid_referers ~example.org/uri;
            return 200 "value $invalid_referer";
        }
        location /regex3 {
            valid_referers ~example.org$;
            return 200 "value $invalid_referer";
        }
        location /uri {
            valid_referers www.example.org/uri;
            return 200 "value $invalid_referer";
        }
        location /sn {
            valid_referers server_names;
            return 200 "value $invalid_referer";
        }
        location /sn_blocked {
            valid_referers blocked server_names;
            return 200 "value $invalid_referer";
        }
        location /wc {
            valid_referers *.example.com *.example.org www.example.* example.*;
            return 200 "value $invalid_referer";
        }
        location /long {
            valid_referers ~.*;
            return 200 "value $invalid_referer";
        }
        location /wc2 {
            valid_referers www.example.*/uri;
            return 200 "value $invalid_referer";
        }
    }
}

EOF

$t->run();

###############################################################################

ok(valid('/simple', 'http://www.example.org'), 'simple');
ok(valid('/simple', 'http://www.example.org/uri'), 'simple uri');
ok(valid('/simple', 'http://www.example.org:8080/uri'), 'simple port uri');
ok(!valid('/simple', 'localhost'), 'simple invalid');
ok(valid('/simple', 'https://www.example.org'), 'https');
ok(!valid('/simple', 'example.com'), 'no scheme');
ok(!valid('/simple'), 'no none');
ok(valid('/none'), 'none');
ok(!valid('/none', ''), 'none empty');

ok(valid('/blocked', 'www.example.org'), 'blocked');
ok(valid('/blocked', 'www.example.com'), 'blocked 2');
ok(valid('/blocked', 'http://su'), 'blocked short');
ok(valid('/blocked', 'foobar'), 'blocked short no scheme');
ok(valid('/blocked', ''), 'blocked empty');

ok(!valid('/simple', 'foobar'), 'small');
ok(valid('/simple', 'http://www.example.org/' . 'a' x 256), 'long uri');
ok(!valid('/simple', 'http://www.example.' . 'a' x 256), 'long hostname');
ok(!valid('/wc', 'http://example.' . 'a' x 256), 'long hostname wildcard');

ok(valid('/long', 'http://' . 'a' x 255), 'long hostname 255');
ok(valid('/long', 'http://' . 'a' x 256), 'long hostname 256');
ok(!valid('/long', 'http://' . 'a' x 257), 'long hostname 257');

ok(valid('/uri', 'http://www.example.org/uri'), 'uri');
ok(valid('/uri', 'http://www.example.org/urii'), 'uri prefix');
ok(!valid('/uri', 'http://www.example.org/uRi'), 'uri case');
ok(valid('/uri', 'http://www.example.org:8080/urii'), 'uri port');
ok(!valid('/uri', 'http://www.example.org/ur'), 'uri invalid len');
ok(!valid('/uri', 'http://www.example.org/urd'), 'uri invalid cmp');

ok(valid('/regex', 'http://www.example.org'), 'regex');
ok(valid('/regex', 'http://www.eXample.org'), 'regex caseless');
ok(valid('/regex', 'http://www.example.org/uri'), 'regex uri');
ok(!valid('/regex', 'http://www.example.com'), 'regex mismatch');
ok(!valid('/regex', 'http://www.eXample.net'), 'regex case mismatch');

ok(valid('/regex2', 'http://www.example.org/uri'), 'regex 2 uri');
ok(!valid('/regex2', 'http://www.example.org'), 'regex 2 no uri');
ok(valid('/regex2', 'http://www.example.org/uRI'), 'regex 2 uri caseless');
ok(valid('/regex3', 'https://www.eXample.org'), 'regex https');

ok(valid('/sn', 'http://localhost'), 'server_names');
ok(valid('/sn', 'http://localHost'), 'server_names caseless');
ok(valid('/sn', 'http://localhost/uri'), 'server_names uri');
ok(valid('/sn', 'http://foobar'), 'server_names regex');
ok(valid('/sn', 'http://foobAr'), 'server_names regex caseless');
ok(valid('/sn', 'http://foobAr/uri'), 'server_names regex caseless uri');
ok(valid('/sn', 'http://anchoredre/uri'), 'server_names regex anchored');
ok(valid('/sn', 'http://foobar/uri'), 'server_names regex uri');
ok(!valid('/sn', 'localhost'), 'server_names no scheme');
ok(!valid('/sn', 'foobar'), 'server_names regex no scheme');
ok(valid('/sn_blocked', 'localhost'), 'server_names no scheme blocked');

ok(valid('/wc', 'http://www.example.org'), 'wildcard head');
ok(valid('/wc', 'http://www.example.net'), 'wildcard tail');
ok(valid('/wc2', 'http://www.example.net/uri'), 'wildcard uri');
ok(valid('/wc2', 'http://www.example.net/urii'), 'wildcard uri prefix');
ok(!valid('/wc2', 'http://www.example.net/uRI'), 'wildcard uri case');

ok(valid('/', 'http://another', 'another'), 'server context');

# server_name below valid_referers

ok(valid('/', 'http://below', 'below'), 'server below');

###############################################################################

sub valid {
	my ($uri, $referer, $host) = @_;
	my $text;

	$host = 'localhost' unless defined $host;

	unless (defined $referer) {
		$text = http_get($uri);
	} else {
		$text = http(<<EOF);
GET $uri HTTP/1.0
Host: $host
Referer: $referer

EOF
	}

	$text =~ /value 1/ && return 0;
	$text =~ /value/ && return 1;
	fail("no valid_referers in $uri");
}

###############################################################################
