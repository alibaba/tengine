#!/usr/bin/perl

# Tests for "timeout" directive.

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

my $t = Test::Nginx->new()->plan(10);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;


events {
    timeout 1;
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream a {
        server localhost:1980;
        server localhost:1981;
    }

    upstream b {
        server localhost:1980;
        server localhost:1981;
        keepalive 5;
    }


    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        
        access_log /tmp/access.log;

        location /1 {
            proxy_pass http://a;
        }

        location /2 {
            proxy_pass http://a;
        }

        location /3 {
            proxy_pass http://b;
        }

        location /4 {
            postpone_output 1;
            set $h "a";
            proxy_pass http://$h/1;
        }

        location /5 {
            set $h "localhost";
            proxy_pass http://$h:1980;
        }

        location /6 {
            echo_location /1;
        }

        location /7 {
            echo_location_async /1;
            echo_location_async /2;
        }

        location /8 {
            echo_sleep 2;
        }

        location /9 {
            postpone_output 1;
            echo "hello";
            echo_sleep 2;
        }
        location /10 {
            echo "hello";
            postpone_output 1;
            echo_location /1;
        }
       
    }

    server {
        listen       127.0.0.1:1980;
        listen       127.0.0.1:1981;
        server_name  localhost;

        location /1 {
            postpone_output 1;
            echo "hello";
            echo_sleep 2;
            echo "world";
        }

        location /2 {
            echo "hello";
            echo_sleep 2;
            echo "world";
        }

        location / {
            echo_sleep 2;
            echo "world";
        }
    }

}

EOF

$t->run();

###############################################################################

http_get('/1');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/2');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/3');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/4');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/5');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/6');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/7');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/8');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/9');
like(`tail -1 /tmp/access.log`, qr/408/s, '');
http_get('/10');
like(`tail -1 /tmp/access.log`, qr/408/s, '');

###############################################################################
