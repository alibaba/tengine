#!/usr/bin/perl

use warnings;
use strict;

use File::Copy;
use File::Basename;
use Test::More;

BEGIN {use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw / :DEFAULT :gzip/ ;

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->plan(4);
my $dir = $t->testdir();
$t->write_file('9000', '9000');
$t->write_file('9001', '9001');
$t->write_file('9002', '9002');
$t->write_file('9003', '9003');
$t->write_file('9004', '9004');
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
}

%%TEST_GLOBALS_DSO%%

http {
    %%TEST_GLOBALS_HTTP%%
    upstream consistent_hash {
        consistent_hash $args;
        server 127.0.0.1:9000 id=9000 weight=1;
        server 127.0.0.1:9001 id=9001 weight=1;
        server 127.0.0.1:9002 id=9002 weight=1;
        server 127.0.0.1:9003 id=9003 weight=1;
    }

    server {
        listen 8080;
        location / {
            proxy_pass http://consistent_hash/;
        }
    }

    server {
        listen 9000;
        location / {
            index 9000;
        }
    }

    server {
        listen 9001;
        location / {
            index 9001;
        }
    }

    server {
        listen 9002;
        location / {
            index 9002;
        }
    }

    server {
        listen 9003;
        location / {
            index 9003;
        }
    }
}

EOF

$t->run();
my $r;
my $res;
$r = http_get('/?abcdef');
$res = getres($r);
like(http_get('/?abcdef'), qr/$res/, "check consistent, the same arg");
unlike(http_get('/?a=asdfdasf'), qr/$res/, "check consistent, different args");
$r = http_get('/?abcdef');
$res = getres($r);
$t->stop();
sleep(1);
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
}

%%TEST_GLOBALS_DSO%%

http {
    %%TEST_GLOBALS_HTTP%%
    upstream consistent_hash {
        consistent_hash $args;
        server 127.0.0.1:9000 id=9000 weight=1 max_fails=0;
        server 127.0.0.1:9001 id=9001 weight=1 max_fails=0;
        server 127.0.0.1:9002 id=9002 weight=1 max_fails=0;
        server 127.0.0.1:9003 id=9003 weight=1 max_fails=0;
        server 127.0.0.1:9004 id=9004 weight=1 max_fails=0;
    }

    server {
        listen 8080;
        location / {
            proxy_pass http://consistent_hash/;
        }
    }

    server {
        listen 9004;
        location / {
            index 9004;
        }
    }
}

EOF

$t->run();
$r = http_get('/?abcdef');
like($r, qr/502/, 'check fallback, no fallback');
unlike($r, qr/$res/, 'check fallback, no fallback');
$t->stop();

###################################################################
#############   blance  ###########################################
###################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
}

%%TEST_GLOBALS_DSO%%
http {
    %%TEST_GLOBALS_HTTP%%
    upstream consistent_hash {
        consistent_hash $args;
        server 127.0.0.1:9000 id=9000 weight=16;
        server 127.0.0.1:9001 id=9001 weight=16;
        server 127.0.0.1:9002 id=9002 weight=16;
        server 127.0.0.1:9003 id=9003 weight=16;
    }

    server {
        listen 8080;
        location / {
            proxy_pass http://consistent_hash/;
        }
    }

    server {
        listen 9000;
        location / {
            index 9000;
        }
    }

    server {
        listen 9001;
        location / {
            index 9001;
        }
    }

    server {
        listen 9002;
        location / {
            index 9002;
        }
    }

    server {
        listen 9003;
        location / {
            index 9003;
        }
    }
}
EOF
sleep(1);
print "blance test 1\n\n";
$t->run();
my @cset = (0..9, 'a'..'z', 'A'..'Z');
my $arg;
my %result;
for (my $count = 1; $count <= 10000; $count++) {
    $arg = join '', map { $cset[int rand @cset] } 0..1000;
    $r = http_get("/?$arg");
    $res = getres($r);
    $result{$res} += 1;
}
print "9000 weight=1  9001 weight=1  9002 weight=1  9003 weight=1\n";
foreach $res (keys(%result)) {
    print ("server $res: $result{$res}\n");
}
$t->stop();
sleep(1);
$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%
worker_processes  1;

events {
}

%%TEST_GLOBALS_DSO%%
http {
    %%TEST_GLOBALS_HTTP%%
    upstream consistent_hash {
        consistent_hash $args;
        server 127.0.0.1:9000 id=9000 weight=1;
        server 127.0.0.1:9001 id=9001 weight=10;
        server 127.0.0.1:9002 id=9002 weight=100;
    }

    server {
        listen 8080;
        location / {
            proxy_pass http://consistent_hash/;
        }
    }

    server {
        listen 9000;
        location / {
            index 9000;
        }
    }

    server {
        listen 9001;
        location / {
            index 9001;
        }
    }

    server {
        listen 9002;
        location / {
            index 9002;
        }
    }

    server {
        listen 9003;
        location / {
            index 9003;
        }
    }
}
EOF
sleep(1);
print "blance test 2\n\n";
$t->run();
foreach $res (keys(%result)) {
    $result{$res} = 0;
}
for (my $count = 1; $count <= 10000; $count++) {
    $arg = join '', map { $cset[int rand @cset] } 0..1000;
    $r = http_get("/?$arg");
    $res = getres($r);
    $result{$res} += 1;
}

print "9000 weight=1  9001 weight=10  9002 weight=100\n";
delete($result{"9003"});
foreach $res (keys(%result)) {
    print ("server $res: $result{$res}\n");
}
print"\n";
$t->stop();
sub getres
{
    my ($c) = @_;
    $c =~ m/\r\n\r\n(\d*)/;
    return $1;
}
