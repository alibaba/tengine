#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx gzip filter module.

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

my $t = Test::Nginx->new()->plan(50);

unlink('/tmp/access.log');
unlink('/tmp/error.log');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

events {
}

http {

    error_log /tmp/error.log debug_http;

    %%TEST_GLOBALS_HTTP%%

    log_env $t1 {
        if ($a && $b && $c);
    }

    log_env $t2 {
        if ($a && $b || $c);
    }

    log_env $t3 {
        if ($a || $b && $c);
    }

    log_env $t4 {
        if ($a || $b || $c);
    }

    log_env $t5 {
        if (($a || $b) && $c);
    }

    log_env $t6 {
        if ($a && ($b || $c));
    }

    log_env $t7 {
        if ($a && ($b && $c));
    }

    log_env $t8 {
        if ($a || ($b || $c));
    }

    log_env $t9 {
        if (($a && $b) && $c);
    }

    log_env $t10 {
        if (($a || $b) || $c);
    }

    log_env $t11 {
        if (($a || $b || $c));
    }

    log_env $t12 {
        if (($a && $b && $c));
    }

    log_format       t1  "t1";
    log_format       t2  "t2";
    log_format       t3  "t3";
    log_format       t4  "t4";
    log_format       t5  "t5";
    log_format       t6  "t6";
    log_format       t7  "t7";
    log_format       t8  "t8";
    log_format       t9  "t9";
    log_format       t10  "t10";
    log_format       t11  "t11";
    log_format       t12  "t12";

    server {
        listen       127.0.0.1:8080;
        server_name  test1.com;
        set $a 0;
        set $b 0;
        set $c 0;
        include loc.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test2.com;
        set $a 1;
        set $b 1;
        set $c 1;
        include loc.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test3.com;
        set $a 1;
        set $b 0;
        set $c 1;
        include loc.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test4.com;
        set $a 0;
        set $b 1;
        set $c 0;
        include loc.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test5.com;
        set $a 1;
        set $b 0;
        set $c 0;
        include loc.conf;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test6.com;
        set $a 0;
        set $b 0;
        set $c 1;
        include loc.conf;
    }
}

EOF

$t->write_file_expand('loc.conf', <<'EOF');

        location /t1 {
            access_log   /tmp/access.log t1 env=$t1;
        }
            
        location /t2 {
            access_log   /tmp/access.log t2 env=$t2;
        }

        location /t3 {
            access_log   /tmp/access.log t3 env=$t3;
        }

        location /t4 {
            access_log   /tmp/access.log t4 env=$t4;
        }

        location /t5 {
            access_log   /tmp/access.log t5 env=$t5;
        }

        location /t6 {
            access_log   /tmp/access.log t6 env=$t6;
        }

        location /t7 {
            access_log   /tmp/access.log t7 env=$t7;
        }

        location /t8 {
            access_log   /tmp/access.log t8 env=$t8;
        }

        location /t9 {
            access_log   /tmp/access.log t9 env=$t9;
        }

        location /t10 {
            access_log   /tmp/access.log t10 env=$t10;
        }

        location /t11 {
            access_log   /tmp/access.log t11 env=$t11;
        }

        location /t12 {
            access_log   /tmp/access.log t12 env=$t12;
        }
EOF

$t->run();

###############################################################################

my_http_get('/t1',  'test1.com', 8080);
my_http_get('/t2',  'test1.com', 8080);
my_http_get('/t3',  'test1.com', 8080);
my_http_get('/t4',  'test1.com', 8080);
my_http_get('/t5',  'test1.com', 8080);
my_http_get('/t6',  'test1.com', 8080);
my_http_get('/t7',  'test1.com', 8080);
my_http_get('/t8',  'test1.com', 8080);
my_http_get('/t9',  'test1.com', 8080);
my_http_get('/t10', 'test1.com', 8080);
my_http_get('/t11', 'test1.com', 8080);
my_http_get('/t12', 'test1.com', 8080);

open("aclog", "/tmp/access.log");
my @lines = <aclog>;
my $num = @lines;

is($num, 0, "all false will not deduce true");

my_http_get('/t1',  'test2.com', 8080);
my_http_get('/t2',  'test2.com', 8080);
my_http_get('/t3',  'test2.com', 8080);
my_http_get('/t4',  'test2.com', 8080);
my_http_get('/t5',  'test2.com', 8080);
my_http_get('/t6',  'test2.com', 8080);
my_http_get('/t7',  'test2.com', 8080);
my_http_get('/t8',  'test2.com', 8080);
my_http_get('/t9',  'test2.com', 8080);
my_http_get('/t10', 'test2.com', 8080);
my_http_get('/t11', 'test2.com', 8080);
my_http_get('/t12', 'test2.com', 8080);

@lines = <aclog>;
$num = @lines;

is($num, 12, "all true will not deduce false");

my_http_get('/t1',  'test3.com', 8080);
my_http_get('/t2',  'test3.com', 8080);
my_http_get('/t3',  'test3.com', 8080);
my_http_get('/t4',  'test3.com', 8080);
my_http_get('/t5',  'test3.com', 8080);
my_http_get('/t6',  'test3.com', 8080);
my_http_get('/t7',  'test3.com', 8080);
my_http_get('/t8',  'test3.com', 8080);
my_http_get('/t9',  'test3.com', 8080);
my_http_get('/t10', 'test3.com', 8080);
my_http_get('/t11', 'test3.com', 8080);
my_http_get('/t12', 'test3.com', 8080);

my $line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

is($line, 't2', '$a && $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't3', '$a || $b && $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't4', '$a || $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't5', '($a || $b) && $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't6', '$a && ($b || $c)');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <aclog>;

is($line, undef, '($a && $b && $c)');

my_http_get('/t1',  'test4.com', 8080);
my_http_get('/t2',  'test4.com', 8080);
my_http_get('/t3',  'test4.com', 8080);
my_http_get('/t4',  'test4.com', 8080);
my_http_get('/t5',  'test4.com', 8080);
my_http_get('/t6',  'test4.com', 8080);
my_http_get('/t7',  'test4.com', 8080);
my_http_get('/t8',  'test4.com', 8080);
my_http_get('/t9',  'test4.com', 8080);
my_http_get('/t10', 'test4.com', 8080);
my_http_get('/t11', 'test4.com', 8080);
my_http_get('/t12', 'test4.com', 8080);

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

isnt($line, 't2', '$a && $b || $c');

isnt($line, 't3', '$a || $b && $c');

is($line, 't4', '$a || $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <aclog>;

is($line, undef, '($a && $b && $c)');

my_http_get('/t1',  'test5.com', 8080);
my_http_get('/t2',  'test5.com', 8080);
my_http_get('/t3',  'test5.com', 8080);
my_http_get('/t4',  'test5.com', 8080);
my_http_get('/t5',  'test5.com', 8080);
my_http_get('/t6',  'test5.com', 8080);
my_http_get('/t7',  'test5.com', 8080);
my_http_get('/t8',  'test5.com', 8080);
my_http_get('/t9',  'test5.com', 8080);
my_http_get('/t10', 'test5.com', 8080);
my_http_get('/t11', 'test5.com', 8080);
my_http_get('/t12', 'test5.com', 8080);

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

isnt($line, 't2', '$a && $b || $c');

is($line, 't3', '$a || $b && $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't4', '$a || $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <aclog>;

is($line, undef, '($a && $b && $c)');

my_http_get('/t1',  'test6.com', 8080);
my_http_get('/t2',  'test6.com', 8080);
my_http_get('/t3',  'test6.com', 8080);
my_http_get('/t4',  'test6.com', 8080);
my_http_get('/t5',  'test6.com', 8080);
my_http_get('/t6',  'test6.com', 8080);
my_http_get('/t7',  'test6.com', 8080);
my_http_get('/t8',  'test6.com', 8080);
my_http_get('/t9',  'test6.com', 8080);
my_http_get('/t10', 'test6.com', 8080);
my_http_get('/t11', 'test6.com', 8080);
my_http_get('/t12', 'test6.com', 8080);

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

is($line, 't2', '$a && $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't3', '$a || $b && $c');

is($line, 't4', '$a || $b || $c');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <aclog>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <aclog>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <aclog>;

is($line, undef, '($a && $b && $c)');

###############################################################################

sub my_http($;%) {
    my ($request, %extra) = @_;
    my $reply;
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        local $SIG{PIPE} = sub { die "sigpipe\n" };
        alarm(2);
        my $s = IO::Socket::INET->new(
            Proto => 'tcp',
            PeerAddr => "127.0.0.1:$extra{port}"
        );  
        log_out($request);
        $s->print($request);
        local $/; 
        select undef, undef, undef, $extra{sleep} if $extra{sleep};
        return '' if $extra{aborted};
        $reply = $s->getline();
        alarm(0);
    };  
    alarm(0);
    if ($@) {
        log_in("died: $@");
        return undef;
    }   
    log_in($reply);
    return $reply;
}


sub my_http_get {
    my ($url, $host, $port) = @_;
    my $r = my_http(<<EOF, 'port', $port);
GET $url HTTP/1.1
Host: $host
Connection: close

EOF
}

###############################################################################
