#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for loading external entities in the nginx xslt filter module.

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

        location /normal {
            xslt_stylesheet %%TESTDIR%%/identity.xslt;
        }

        location /entity_file {
            xslt_stylesheet %%TESTDIR%%/identity.xslt;
        }

        location /entity_allowed {
            xml_external_entities on;
            xslt_stylesheet %%TESTDIR%%/identity.xslt;
        }

        location /entity_net {
            xslt_stylesheet %%TESTDIR%%/identity.xslt;
        }

        location /predefined {
            xslt_stylesheet %%TESTDIR%%/identity.xslt;
        }
    }
}

EOF

# identity stylesheet, passes the document through unchanged so that entity
# expansion (or lack thereof) is visible in the response body

$t->write_file('identity.xslt', <<'EOF');
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="no"/>
  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
EOF

$t->write_file('secret.txt', "secret_data\n");

# %%TESTDIR%% is expanded to the absolute path of the test directory so the
# file:// URI is valid regardless of where the test suite is run

my $doc =
    '<?xml version="1.0"?>' . "\n"
    . '<!DOCTYPE root [' . "\n"
    . '  <!ENTITY secret SYSTEM "file://%%TESTDIR%%/secret.txt">' . "\n"
    . ']>' . "\n"
    . '<root><data>&secret;</data></root>' . "\n";

$t->write_file_expand('entity_file', $doc);
$t->write_file_expand('entity_allowed', $doc);

$t->write_file('entity_net',
    '<?xml version="1.0"?>' . "\n"
    . '<!DOCTYPE root [' . "\n"
    . '  <!ENTITY net SYSTEM "http://127.0.0.1:8081/should_not_connect">' . "\n"
    . ']>' . "\n"
    . '<root><data>&net;</data></root>' . "\n");

$t->write_file('predefined',
    '<?xml version="1.0"?>' . "\n"
    . '<root><data>&lt;angle&gt; &amp; entity</data></root>' . "\n");

$t->write_file('normal', '<root><data>hello</data></root>');

$t->try_run('no xml_external_entities')->plan(7);

###############################################################################

# normal transform still works
like(http_get('/normal'), qr!<data>hello</data>!, 'normal transform works');

# file external entity is not loaded by default
unlike(http_get('/entity_file'), qr/secret_data/, 'file entity blocked');

# the element is preserved, the entity expands to nothing
like(http_get('/entity_file'), qr!<data></data>|<data/>!, 'element preserved');

# with xml_external_entities on the same document loads the entity
like(http_get('/entity_allowed'), qr/secret_data/,
	'entity loaded when enabled');

# http external entity does not crash the worker
like(http_get('/entity_net'), qr/200 OK/, 'network entity does not crash');

# and is not loaded
unlike(http_get('/entity_net'), qr/should_not_connect/,
	'network entity blocked');

# predefined entities keep working
like(http_get('/predefined'), qr!&lt;angle&gt; &amp; entity!,
	'predefined entities work');

###############################################################################
