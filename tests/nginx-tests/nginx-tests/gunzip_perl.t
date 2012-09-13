#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for gunzip filter module with perl module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT :gzip /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { require IO::Compress::Gzip; };
Test::More::plan(skip_all => "IO::Compress::Gzip not found") if $@;

my $t = Test::Nginx->new()->has(qw/http gunzip perl/)->plan(2)
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

        gunzip on;

        location / {
            perl 'sub {
                my $r = shift;
                $r->header_out("Content-Encoding", "gzip");
                $r->send_http_header("text/plain");
                return OK if $r->header_only;
                use IO::Compress::Gzip;
                my $in = "TEST";
                my $out;
                IO::Compress::Gzip::gzip(\\$in => \\$out);
                $r->print($out);
                return OK;
            }';
        }
    }
}

EOF

$t->run();

###############################################################################

http_gzip_like(http_gzip_request('/'), qr/TEST/, 'perl response gzipped');
like(http_get('/'), qr/TEST/, 'perl response gunzipped');

###############################################################################
