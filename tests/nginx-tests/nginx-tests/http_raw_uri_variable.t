#!/usr/bin/perl

# (C) Maxim Dounin
# (C) flygoast

# Tests for 'raw_uri' built-in variable.

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

my $t = Test::Nginx->new()->has(qw/http rewrite addition/)->plan(18)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-RAW-URI     $raw_uri;
            return 200;
        }

        location /sr {
            types { }
            default_type text/html;
            add_before_body /addition;
            return 200;
        }

        location /addition {
            return 200 "X-RAW-URI: $raw_uri\r\n";
        }

        location /lua {
            default_type 'text/html';

            content_by_lua '
                local res = ngx.location.capture("/addition");
                ngx.print(res.body);
                ';
        }
    }
}

EOF

$t->run();

###############################################################################

raw_uri('/rawuri', '/rawuri', 'uri');
raw_uri('/rawuri%3F', '/rawuri%3F', 'escaped uri');
raw_uri('/rawuri?arg=foo', '/rawuri', 'uri with arguments');
raw_uri('/rawuri?arg=%2F', '/rawuri', 'uri with escaped arguments');
raw_uri('/rawuri%3F?arg=foo', '/rawuri%3F', 'escaped uri with arguments');
raw_uri('/rawuri%3F?arg=%2F', '/rawuri%3F',
    'escaped uri with escaped arguments');
raw_uri('/sr', '/sr', 'uri in subrequest');
raw_uri('/sr%3F', '/sr%3F', 'escaped uri in subrequest');
raw_uri('/sr?arg=foo', '/sr', 'uri with arguments in subrequest');
raw_uri('/sr?arg=%2F', '/sr', 'uri with escaped arguments in subrequest');
raw_uri('/sr%3F?arg=foo', '/sr%3F',
    'escaped uri with arguments in subrequest');
raw_uri('/sr%3F?arg=%2F', '/sr%3F',
    'escaped uri with escaped arguments in subrequest');
raw_uri('/lua', '/lua', 'uri in lua subrequest');
raw_uri('/lua%3F', '/lua%3F', 'escaped uri in lua subrequest');
raw_uri('/lua?arg=foo', '/lua', 'uri with arguments in lua subrequest');
raw_uri('/lua?arg=%2F', '/lua', 'uri with escaped arguments in lua subrequest');
raw_uri('/lua%3F?arg=foo', '/lua%3F',
    'escaped uri with arguments in lua subrequest');
raw_uri('/lua%3F?arg=%2F', '/lua%3F',
    'escaped uri with escaped arguments in lua subrequest');

###############################################################################

sub raw_uri {
	my ($url, $value, $name) = @_;
	my $data = http_get($url);
	if ($data !~ qr!^X-RAW-URI: (.*?)\x0d?$!ms) {
		fail($name);
		return;
	}
	my $raw_uri = $1;
	is($raw_uri, $value, $name);
}

###############################################################################
