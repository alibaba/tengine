#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx xslt filter module.

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

my $t = Test::Nginx->new()->has(qw/http xslt/);

$t->set_dso("ngx_http_xslt_module", "ngx_http_xslt_module.so");
$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        default_type text/xml;

        location /x1 {
            xslt_stylesheet %%TESTDIR%%/test.xslt
                            param1='value1':param2=/root param3='value%33';
        }
        location /x2 {
            xslt_stylesheet %%TESTDIR%%/test.xslt;
            xslt_param param1 "'value1'";
            xslt_param param2 "/root";
            xslt_string_param param3 "value3";
        }
        location /x3 {
            xslt_stylesheet %%TESTDIR%%/test.xslt
                            param1='value1':param2=/root;
            xslt_string_param param3 "value3";
        }
    }
}

EOF

$t->write_file('test.xslt', <<'EOF');

<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:output method="html"/>

<xsl:param name="param1"/>
<xsl:param name="param2"/>
<xsl:param name="param3"/>

<xsl:template match="/">
param1=<xsl:value-of select="$param1"/>
param2=<xsl:value-of select="$param2"/>
param3=<xsl:value-of select="$param3"/>
</xsl:template>

</xsl:stylesheet>

EOF

$t->write_file('x1', '<root>data</root>');
$t->write_file('x2', '<root>data</root>');
$t->write_file('x3', '<root>data</root>');

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};

plan(skip_all => 'no xslt_param') if $@;
$t->plan(3);

###############################################################################

like(http_get("/x1"), qr!200 OK.*param1=value1.*param2=data.*param3=value3!ms,
	'params from xslt_stylesheet');
like(http_get("/x2"), qr!200 OK.*param1=value1.*param2=data.*param3=value3!ms,
	'params from xslt_param/xslt_string_param');
like(http_get("/x3"), qr!200 OK.*param1=value1.*param2=data.*param3=value3!ms,
	'mixed');

###############################################################################
