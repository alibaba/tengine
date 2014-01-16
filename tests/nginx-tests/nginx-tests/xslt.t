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

my $t = Test::Nginx->new()->has(qw/http xslt/)->plan(5);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        default_type text/xml;

        location /x1 {
            xslt_stylesheet %%TESTDIR%%/test.xslt;
        }
        location /x2 {
            xslt_stylesheet %%TESTDIR%%/test.xslt
                            param1='value1':param2=/root param3='value%33';
        }
        location /x3 {
            xml_entities %%TESTDIR%%/entities.dtd;
            xslt_stylesheet %%TESTDIR%%/test.xslt;
        }
        location /x4 {
            xslt_stylesheet %%TESTDIR%%/first.xslt;
            xslt_stylesheet %%TESTDIR%%/test.xslt;
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
test xslt result
param1=<xsl:value-of select="$param1"/>
param2=<xsl:value-of select="$param2"/>
param3=<xsl:value-of select="$param3"/>
data=<xsl:value-of select="/root"/>
</xsl:template>

</xsl:stylesheet>

EOF

$t->write_file('first.xslt', <<'EOF');

<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:template match="/">
<root>other <xsl:value-of select="/root"/></root>
</xsl:template>

</xsl:stylesheet>

EOF

$t->write_file('entities.dtd', '<!ENTITY test "test entity">' . "\n");
$t->write_file('x1', '<empty/>');
$t->write_file('x2', '<root>data</root>');
$t->write_file('x3', '<!DOCTYPE root><root>&test;</root>');
$t->write_file('x4', '<root>data</root>');

$t->run();

###############################################################################

like(http_get("/x1"), qr!200 OK.*test xslt result!ms, 'simple');
like(http_get("/x1"), qr!200 OK.*Content-Type: text/html!ms, 'content type');
like(http_get("/x2"), qr!200 OK.*param1=value1.*param2=data.*param3=value3!ms,
	'params');
like(http_get("/x3"), qr!200 OK.*data=test entity!ms, 'entities');
like(http_get("/x4"), qr!200 OK.*data=other data!ms, 'several stylesheets');

###############################################################################
