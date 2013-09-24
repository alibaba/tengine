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

my $t = Test::Nginx->new()->has(qw/http rewrite/)->plan(6)
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
