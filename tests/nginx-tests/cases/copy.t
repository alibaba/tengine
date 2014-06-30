#!/usr/bin/perl

# (C) Xiaochen Wang <xiaochen.wxc@alibaba-inc.com>
# (C) Alibaba, Inc
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

my $t = Test::Nginx->new()->plan(58)
        ->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
}

# for --with-http_copy_module=shared
#dso {
#    load ngx_http_copy_module.so;
#}

http {
    access_log    off;
    client_body_buffer_size 10m;
    client_max_body_size 10m;

    # copy/proxy_pass sever
    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        root %%TESTDIR%%;

        location = /proxy {
                rewrite ^ / break;
                http_copy 127.0.0.1:8082 multiple=10;
                http_copy_keepalive off;
                proxy_pass http://127.0.0.1:8081;
        }

        location /chunk/ {
                http_copy 127.0.0.1:8082 multiple=1;
                http_copy_keepalive connections=1000;
                echo "RECEIVED-REQUEST";
        }

        location = /post {
                if ($request_method = POST) {
                        set $copyon "true";
                }
                http_copy 127.0.0.1:8082 multiple=10 switch_on=$copyon;
                http_copy_keepalive on connections=1000;
                proxy_pass http://127.0.0.1:8081;
        }

        location = /serial_get {
                http_copy 127.0.0.1:8082 multiple=1000 serial;
                echo "RECEIVED-REQUEST";
        }

        location = /serial_get_10000 {
                http_copy 127.0.0.1:8082 multiple=10000 serial;
                echo "RECEIVED-REQUEST";
        }

        location = /http_copy_status {
                http_copy_status;
        }

        location = /test_switch_on {

                set $copyon "false";        # can delete this line

                if ($arg_switch_on = ON) {
                        set $copyon "true";
                }

                http_copy 127.0.0.1:8082 multiple=1 switch_on=$copyon;
                proxy_pass http://127.0.0.1:8081;
        }

        location = /multi_copy {

                set $copyon "true";
                set $copyoff "false";

                http_copy 127.0.0.1:8081 multiple=5;
                http_copy 127.0.0.1:8082 multiple=3 switch_on=$copyon;
                http_copy 127.0.0.1:8081 multiple=1 switch_on=$copyoff;
                http_copy 127.0.0.1:8082 multiple=7;

                echo "RECEIVED-REQUEST";
        }
    }

    # proxy_pass backend server
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        root %%TESTDIR%%;

        location / {
                echo $arg_info;
        }

        location = /test_switch_on {
                echo -n $arg_switch_on;
        }

        location = /post {
                echo_read_request_body;
                echo -n $request_body;
        }

        location = /multi_copy {
            return 200 "1234567890";
        }
    }

    # http_copy backend server
    server {
        listen       127.0.0.1:8082;
        keepalive_requests 20000;
        server_name  localhost;
        chunked_transfer_encoding on;

        location / {
                return 200;
        }

        location /chunk/ {
                more_clear_headers 'Content-Length';
                root %%TESTDIR%%;
        }

        location = /post {
                echo_read_request_body;
                echo -n $request_body;
        }

        location /serial_get {
                echo -n "helloworld";        # echo 10 bytes
        }

        location = /multi_copy {
                return 200 "12345";
        }
    }
}

EOF

my $status;

#############################################################
# 10x copy
#############################################################

$t->run();

# test whether backend server can handle original request
like("ok", qr/o/, 'ok');        # qr/o/ means 'o' is sub string of "ok"

like(http_get('/proxy?info=test_backend_server'), qr/test_backend_server/, 'request backend server');

sleep(1);
$status = http_get('/http_copy_status');
like($status, qr/Request: 10/, 'test status');
like($status, qr/Response\(OK\): 10/, 'test status');
like($status, qr/Connect: 10/, 'test status');

like(http_get('/proxy?info=backend_server_can_reponse_this_request'), qr/backend_server_can_reponse_this_request/, 'request backend server');

sleep(1);
$status = http_get('/http_copy_status');
like($status, qr/Request: 20/, 'test status');
like($status, qr/Response\(OK\): 20/, 'test status');
like($status, qr/Connect: 20/, 'test status');

#############################################################
# response with chunk body
#############################################################

# create static file
my $d = $t->testdir();
mkdir("$d/chunk");

$t->write_file("chunk/static", '1' x 8);
http_get_11('/chunk/static');
sleep(1);
like(http_get('/http_copy_status'), qr/read\(chunk\): 8 bytes/, 'read chunk 8 bytes');

$t->write_file("chunk/static", '1' x 8000);
http_get_11('/chunk/static');
sleep(1);
like(http_get('/http_copy_status'), qr/read\(chunk\): 8008 bytes/, 'read chunk 8000 bytes');

$t->write_file("chunk/static", '1' x 80000000);
http_get_11('/chunk/static');
sleep(1);        # let backend handle large static file
like(http_get('/http_copy_status'), qr/read\(chunk\): 80008008 bytes/, 'read chunk 80000000 bytes');

$t->stop();

#############################################################
# post input body
#############################################################

$t->run();

# test http_copy switch_on directive for $request_method
http_get('/post');        # GET request wont be copied

# test request containing input body with 'multiple=10'
like(http_post('/post', '1' x 8), qr/Content-Length: 8/, 'proxy input body 8 bytes');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 80 bytes/, 'copy input body 8 bytes');

like(http_post('/post', '1' x 8000), qr/Content-Length: 8000/, 'proxy input body 8000 bytes');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 80080 bytes/, 'copy input body 8000 bytes');

like(http_post('/post', '1' x 80000), qr/Content-Length: 80000/, 'proxy input body 80000 bytes');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 880080 bytes/, 'copy input body 80000 bytes');

like(http_post('/post', '1' x 1000000), qr/Content-Length: 1000000/, 'proxy input body ~1M bytes');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 10880080 bytes/, 'copy input body ~1M bytes');

like(http_post('/post', '1' x 3000000), qr/Content-Length: 3000000/, 'proxy input body ~3M');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 40880080 bytes/, 'copy input body ~3M bytes');

like(http_post('/post', '1' x 10000000), qr/Content-Length: 10000000/, 'proxy input body ~10M bytes');
sleep(1);
like(http_get('/http_copy_status'), qr/read: 140880080 bytes/, 'copy input body ~10M bytes');
$t->stop();

#############################################################
# serial copy
#############################################################

$t->run();

# test copying GET requests serially
like(http_get('/serial_get'), qr/RECEIVED-REQUEST/, 'copy serial GET 1000 requests');
sleep(1);
$status = http_get('/http_copy_status');
like($status, qr/Request: 1000/, 'test status');
like($status, qr/Response\(OK\): 1000/, 'test status');
like($status, qr/Connect: 1/, 'test status');
like($status, qr/read: 10000 bytes/, 'test status');

like(http_get('/serial_get_10000'), qr/RECEIVED-REQUEST/, 'copy serial GET 10000 requests');
sleep(4);
$status = http_get('/http_copy_status');
like($status, qr/Request: 11000/, 'test status');
like($status, qr/Response\(OK\): 11000/, 'test status');
like($status, qr/Connect: 2/, 'test status');
like($status, qr/read: 110000 bytes/, 'test status');

$t->stop();


#############################################################
# switch on/off
#############################################################
$t->run();

# switch off
like(http_get('/test_switch_on'), qr/Content-Length: 0/, 'copy switch on - false');
like(http_get('/test_switch_on?switch_on=OFF'), qr/OFF/, 'copy switch on - false');
like(http_get('/test_switch_on?switch_on='), qr/Content-Length: 0/, 'copy switch on - false');
like(http_get('/http_copy_status'), qr/Request: 0/, 'test status');
# switch on
like(http_get('/test_switch_on?switch_on=ON'), qr/ON/, 'copy switch on - true');
like(http_get('/http_copy_status'), qr/Request: 1/, 'test status');
# switch off
like(http_get('/test_switch_on?switch_on=OFF'), qr/OFF/, 'copy switch on - false');
like(http_get('/http_copy_status'), qr/Request: 1/, 'test status');
# switch on
like(http_get('/test_switch_on?switch_on=ON'), qr/ON/, 'copy switch on - true');
like(http_get('/http_copy_status'), qr/Request: 2/, 'test status');

$t->stop();

#############################################################
# multi copy
#############################################################
$t->run();
like(http_get('/multi_copy'), qr/RECEIVED-REQUEST/, 'multi copy');
sleep(2);
$status = http_get('/http_copy_status');
like($status, qr/Request: 15/, 'test status');
like($status, qr/Response\(OK\): 15/, 'test status');
like($status, qr/read: 100 bytes/, 'multi copy 100 bytes');
$t->stop();

#############################################################
# check config
#############################################################

$t->write_file_expand('nginx.conf', <<'EOF');

master_process off;
daemon         off;

events {
}

# for --with-http_copy_module=shared
#dso {
#    load ngx_http_copy_module.so;
#}

http {
    access_log    off;
    client_body_buffer_size 10m;
    client_max_body_size 10m;

    # copy/proxy_pass sever
    server {
        listen       127.0.0.1:8080;
        server_name  localhost;
        root %%TESTDIR%%;

        http_copy 127.0.0.1:8081 multiple=5;

        location = /on {
            echo "ON";
        }

        location = /off {
            http_copy off;
            echo "OFF";
        }

        location = /http_copy_status {
            http_copy off;
            http_copy_status;
        }

        location = /rewrite {
            rewrite .* /rewrite_to last;
        }

        location = /rewrite_to {
            http_copy 127.0.0.1:8081 multiple=1;
            echo "REWRITE_TO";
        }

        location = /rewrite_uri {
            rewrite .* /rewrite_to_uri last;
        }

        location = /rewrite_to_uri {
            http_copy 127.0.0.1:8081 multiple=1;
            http_copy_unparsed_uri off;
            echo "REWRITE_TO_URI";
        }
    }

    # proxy_pass backend server
    server {
        listen       127.0.0.1:8081;
        server_name  localhost;
        root %%TESTDIR%%;

        log_format copy "uri: $request_uri";
        access_log %%TESTDIR%%/copy.log copy;

        location / {
            return 200 "1234567890";
        }

        location /rewrite {
            return 200 "uri: $request_uri";
        }
    }
}

EOF

print("\n=== check http_copy configure===\n");

$t->run();
like(http_get('/off'), qr/OFF/, 'http_copy off');
like(http_get('/on'), qr/ON/, 'http_copy on');
like(http_get('/off'), qr/OFF/, 'http_copy off');
sleep(1); http_get('/http_copy_status');    # test copy off & copy status
$status = http_get('/http_copy_status');
like($status, qr/Request: 5/, 'test status');
like($status, qr/Response\(OK\): 5/, 'test status');
like($status, qr/read: 50 bytes/, 'copy 50 bytes');
$t->stop();

# test http_copy_unparsed_uri directivce

$t->run();
like(http_get('/rewrite?unparsed_uri=on'), qr/REWRITE_TO/, 'http_copy unparsed_uri');
like(http_get('/rewrite_uri?unparsed_uri=off'), qr/REWRITE_TO_URI/, 'http_copy rewrited uri');
$t->stop();

my $log;

{
        open LOG, $t->testdir() . '/copy.log'
                or die("Can't open nginx access log file.\n");
        local $/;
        $log = <LOG>;
        close LOG;
}

like($log, qr/uri: \/rewrite\?unparsed_uri=on/, 'http_copy unparsed_uri log');
like($log, qr/uri: \/rewrite_to_uri\?unparsed_uri=off/, 'http_copy rewrite_uri log');

#############################################################
# auxiliary function
#############################################################

# Must add Connection: close, otherwise nginx will hangup http() because keepalive

# chunked encoding is supported by HTTP/1.1
sub http_get_11 {
        return http(<<EOF);
GET @_ HTTP/1.1
Host: localhost
Connection: close

EOF
}

sub http_post {
        my ($url, $body) = @_;
        my $body_length = length($body);
        my $r = http(<<EOF);
POST $url HTTP/1.1
Host: localhost
Content-Length: $body_length
Connection: close

$body
EOF
}
