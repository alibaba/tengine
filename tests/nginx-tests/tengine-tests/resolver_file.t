#!/usr/bin/perl

# (C) Xiaochen Wang

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

sub http_get_host($;$;%) {
    my ($url, $host, %extra) = @_;
    return http(<<EOF, %extra);
GET $url HTTP/1.0
Host: $host

EOF
}

my $t = Test::Nginx->new()->plan(1);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

master_process off;
daemon         off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    resolver_file %%TESTDIR%%/resolv.conf;
    resolver_timeout 1s;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://$http_host:8082;
        }
    }

    server {
        listen      127.0.0.1:8082;
        return 200 "resolved success";
    }
}

EOF

$t->write_file_expand('resolv.conf', <<'EOF');
nameserver 127.0.0.1
EOF

$t->run();

# error_log log levels

SKIP: {

skip "no --with-debug", 1 unless $t->has_module('--with-debug');

http_get_host("/", "test.com");

# example for error.log
# Run dns daemon
#   2023/05/28 13:54:02 [debug] 1210#0: connect to 127.0.0.1:53, fd:11 #2
#
# Not run dns daemon
#   2023/05/28 13:56:26 [debug] 1302#0: connect to 127.0.0.1:53, fd:11 #2
#   2023/05/28 13:56:26 [error] 1302#0: send() failed (111: Connection refused) while resolving, resolver: 127.0.0.1:53
like($t->read_file("error.log"),
     qr/\[debug\].*connect to 127.0.0.1:53, fd:/,
     'log: connect dns server');

}

$t->stop();
