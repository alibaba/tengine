#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for dumped nginx configuration (nginx -T).
# Among other things, test that configuration blocks are properly processed.

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

my $t = Test::Nginx->new()->has(qw/http map/);

plan(skip_all => 'no config dump') unless $t->has_version('1.9.2');

$t->plan(10)->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

include %%TESTDIR%%/inc.conf;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $args $x {
        default  0;
        foo      bar;
        include  map.conf;
    }

    upstream u {
        server 127.0.0.1:8081;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('inc.conf', 'include inc2.conf;');
$t->write_file('inc2.conf', '#inc2.conf');
$t->write_file('map.conf', '#map.conf;');

$t->run();

###############################################################################

my $d = $t->testdir;

my $dump = $t->dump_config();
like($dump, qr!^# configuration file $d/nginx.conf:$!m, 'nginx.conf found');
like($dump, qr!^# configuration file $d/inc.conf:$!m, 'inc.conf found');
like($dump, qr!^# configuration file $d/inc2.conf:$!m, 'inc2.conf found');
like($dump, qr!^# configuration file $d/map.conf:$!m, 'map.conf found');

is(getconf($t, $dump, 'nginx.conf'), $t->read_file('nginx.conf'), 'content');
is(getconf($t, $dump, 'inc.conf'), $t->read_file('inc.conf'), 'content inc');
is(getconf($t, $dump, 'map.conf'), $t->read_file('map.conf'), 'content inc 2');

unlink($t->testdir . "/inc.conf");
unlink($t->testdir . "/map.conf");

$dump = $t->dump_config();
unlike($dump, qr!file $d/inc.conf!, 'missing inc.conf');
unlike($dump, qr!file $d/map.conf!, 'missing map.conf');
like($dump, qr!file $d/nginx.conf test failed!, 'test failed');

$t->write_file('inc.conf', 'include inc2.conf;');
$t->write_file('inc2.conf', '#inc2.conf');
$t->write_file('map.conf', '#map.conf;');

###############################################################################

sub getconf {
	my ($t, $string, $conf) = @_;
	my $prefix = "# configuration file $d/$conf:\n";
	my $offset = index($string, $prefix) + length($prefix);
	my $len = length($t->read_file($conf));
	my $s = substr($string, $offset, $len);
	$s =~ tr/\r//d;
	return $s;
}
