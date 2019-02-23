#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for sub filter and subrequests.

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

my $t = Test::Nginx->new()->has(qw/http sub ssi xslt/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    types {
        text/html html;
        text/xml  xml;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            ssi on;
            sub_filter notfoo bar;
        }

        location /xslt {
            ssi on;
            sub_filter_types *;
            sub_filter root>foo bar;
            xslt_stylesheet test.xslt;
        }
    }
}

EOF

$t->write_file('index.html', '<!--#include virtual="/not.html" --> truncated');
$t->write_file('not.html', 'response is not');

$t->write_file('xslt.html', '<!--#include virtual="/xslt.xml" --> truncated');
$t->write_file('xslt.xml', '<root>test</root>');
$t->write_file('test.xslt', <<'EOF');

<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="html"/>
<xsl:strip-space elements="*"/>
<xsl:template match="/">response is not</xsl:template>
</xsl:stylesheet>

EOF

$t->run();

###############################################################################

like(http_get('/index.html'), qr/not truncated/, 'subrequest partial match');
like(http_get('/xslt.html'), qr/not.*truncated/ms, 'partial match and xslt');

###############################################################################
