#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for escaping/unescaping in rewrite module.

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

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location /t1 {
            rewrite ^ $arg_r? redirect;
        }

        location /t2 {
            rewrite ^ http://example.com$request_uri? redirect;
        }

        location /t3 {
            rewrite ^ http://example.com$uri redirect;
        }

        location /t4 {
            rewrite ^(.*) http://example.com$1 redirect;
        }

        location /t5 {
            rewrite ^ http://example.com/blah%20%3Fblah redirect;
        }

        location /t6 {
            rewrite ^ http://example.com/blah%20%2Fblah redirect;
        }
    }
}

EOF

mkdir($t->testdir() . '/directory');

$t->run();

###############################################################################

# Some rewrites and expected (?) behaviour
#
# /t1?r=http%3A%2F%2Fexample.com%2F%3Ffrom
# rewrite ^ $arg_r? redirect;
# expected: http://example.com/?from
# got:      http://example.com/?from
#
# /t1?r=http%3A%2F%2Fexample.com%0D%0Asplit
# rewrite ^ $arg_r? redirect;
# expected: http://example.com%0D%0Asplit
# got:      http://example.com%0D%0Asplit
#
# /t1?r=http%3A%2F%2Fexample.com%2F%3Ffrom%3Dblah
# rewrite ^ $arg_r? redirect;
# expected: http://example.com/?from=blah
# got:      http://example.com/?from%3Dblah
#
# /blah%3Fblah
# rewrite ^ http://example.com$request_uri? redirect;
# expected: http://example.com/blah%3Fblah
# got:      http://example.com/blah?blah
#
# /blah%3Fblah
# rewrite ^ http://example.com$uri redirect;
# expected: http://example.com/blah%3Fblah
# got:      http://example.com/blah?blah
#
# /blah%3Fblah
# rewrite ^(.*) http://example.com$1 redirect;
# expected: http://example.com/blah%3Fblah
# got:      http://example.com/blah?blah
#
# /
# rewrite ^ http://example.com/blah%3Fblah redirect;
# expected: http://example.com/blah%3Fblah
# got:      http://example.com/blah?blah
#

location('/t1?r=http%3A%2F%2Fexample.com%2F%3Ffrom',
	'http://example.com/?from', 'escaped argument');

location('/t1?r=http%3A%2F%2Fexample.com%0D%0Asplit',
	'http://example.com%0D%0Asplit', 'escaped argument header splitting');

TODO: {
local $TODO = 'not yet';

# Fixing this cases will require major changes to the whole approach and
# likely to break some currently working cases.  On the other hand, current
# behaviour is far from acceptable.  Should be carefully thought.

location('/t1?r=http%3A%2F%2Fexample.com%2F%3Ffrom%3Dblah',
	'http://example.com/?from=blah', 'escaped argument with complex query');

location('/t2/blah%20%3Fblah',
	'http://example.com/t2/blah%20%3Fblah', 'escaped $request_uri');

location('/t3/blah%20%3Fblah',
	'http://example.com/t3/blah%20%3Fblah', 'escaped $uri');

location('/t4/blah%20%3Fblah',
	'http://example.com/t4/blah%20%3Fblah', 'escaped $1');

location('/t5',
	'http://example.com/blah%20%3Fblah', 'escaped static');

location('/t5?arg=blah',
	'http://example.com/blah%20%3Fblah?arg=blah',
	'escaped static with argument');

location('/t6',
	'http://example.com/blah%20%2Fblah', 'escaped static slash');

}

###############################################################################

sub location {
	my ($url, $value, $name) = @_;
	my $data = http_get($url);
	if ($data !~ qr!^Location: (.*?)\x0d?$!ms) {
		fail($name);
		return;
	}
	my $location = $1;
	is($location, $value, $name);
}

###############################################################################
