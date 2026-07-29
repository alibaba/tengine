#!/usr/bin/perl


###############################################################################

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

daemon         off;

events {
}

http {
    access_log    off;

    server {
        listen       127.0.0.1:9999;
        server_name  localhost;
        add_header T1 proxy;
        location / {
            return 200;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;


        root %%TESTDIR%%;
        location / {
            add_header T1 1;
            add_header T1 2;
            index index.html;
        }

        location /append {
            add_header T1 1;
            append_header T1 2;
            return 200;
        }

        location /p {
            append_header T1 2;
            proxy_pass http://127.0.0.1:9999;
        }

        location /se {
            append_header_separator |;
            append_header T1 2;
            proxy_pass http://127.0.0.1:9999;
        }
    }
}

EOF
$t->write_file('/index.html', '127.0.0.1');


$t->run();

like(http_head('/'), qr/T1: 2/, 'add header');
like(http_head('/append'), qr/T1: 1, 2/, 'append header');
like(http_head('/p'), qr/T1: proxy, 2/, 'append header for proxy');
like(http_head('/se'), qr/T1: proxy|2/, 'append header separator by "|"');


$t->stop();

