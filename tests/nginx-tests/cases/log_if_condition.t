#!/usr/bin/perl

# (C) cfsego

# Tests for logical operator and group operator in "if".

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

my $t = Test::Nginx->new()->plan(61);

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

open("access_log", "/tmp/access.log");
my @lines = <access_log>;
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

@lines = <access_log>;
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

my $line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

is($line, 't2', '$a && $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't3', '$a || $b && $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't4', '$a || $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't5', '($a || $b) && $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't6', '$a && ($b || $c)');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <access_log>;

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

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

isnt($line, 't2', '$a && $b || $c');

isnt($line, 't3', '$a || $b && $c');

is($line, 't4', '$a || $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <access_log>;

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

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

isnt($line, 't2', '$a && $b || $c');

is($line, 't3', '$a || $b && $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't4', '$a || $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <access_log>;

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

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't1', '$a && $b && $c');

is($line, 't2', '$a && $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't3', '$a || $b && $c');

is($line, 't4', '$a || $b || $c');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't5', '($a || $b) && $c');

isnt($line, 't6', '$a && ($b || $c)');

isnt($line, 't7', '$a && ($b && $c)');

is($line, 't8', '$a || ($b || $c)');

$line = <access_log>;
$line =~ s/\s+$//;

isnt($line, 't9', '($a && $b) && $c');

is($line, 't10', '($a || $b) || $c');

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 't11', '($a || $b || $c)');

$line = <access_log>;

is($line, undef, '($a && $b && $c)');

############################################################################

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon         off;

worker_processes  1;

events {
}

http {

    log_format wd "write";

    error_log /tmp/error.log debug_http;
    access_log /tmp/access.log wd;

    %%TEST_GLOBALS_HTTP%%

    # equivalent $a && $b && $c
    log_env $t1 {
        if ($a) and;
        if ($b) and;
        if ($c);
    }

    # equivalent $a && $b || $c
    log_env $t2 {
        if ($a && $b);
        if ($c);
        sample 0.2;
    }

    map $r $x {
        0   1;
        default 0;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  test1.com;

        location /t1 {
            set $a 1;
            set $b 0;
            set $c 1;
            # equivalent $a && $b || $c
            log_condition {
                if ($a) and;
                if ($b);
                if ($c);
            }
        }

        location /t2 {
            set $a 1;
            set $b 0;
            set $c 1;
            log_condition {
                if ($a) and;
                if ($b);
                if ($c);
            }
            access_log /tmp/access.log wd env=$t1;
        }

        location /t3 {
            set $a 1;
            set $b 1;
            set $c 1;

            access_log /tmp/access.log wd env=$t1 ratio=.1;
        }

        location /t4 {
            set $a 0;
            set $b 1;
            set $c 1;

            access_log /tmp/access.log wd env=$t2;
        }

        location /t5 {
            set $a 0;
            set $b 1;
            set $c 1;

            access_log /tmp/access.log wd env=$t2 ratio=0.1;
        }

        location /t6 {
            set $a 1;
            set $b 0;
            set $c 1;
            log_condition {
                if ($a) and;
                if ($b);
                if ($c);
                sample 0.5;
            }
        }

        location /t7 {
            set $a 1;
            set $b 0;
            set $c 1;
            log_condition {
                if ($a) and;
                if ($b);
                if ($c);
                sample 0.5;
            }
            access_log /tmp/access.log wd env=$t2;
        }

        location /t8 {
            set $a 1;
            set $b 0;
            set $c 1;
            log_condition {
                if ($a) and;
                if ($b);
                if ($c);
                sample 0.5;
            }
            access_log /tmp/access.log wd env=$t2 ratio=0.1;
        }

        location /t9 {
            set $r 0;
            access_log /tmp/access.log wd env=$r;
        }

        location /t10 {
            set $r 0;
            access_log /tmp/access.log wd env=$x;
        }

        location /t11 {
            set $r 1;
            access_log /tmp/access.log wd env=$r ratio=0.1;
        }
    }
}
EOF

close(access_log);
unlink('/tmp/access.log');

$t->stop();
$t->run();

my_http_get('/t1', 'test.com', 8080);

open("access_log", "/tmp/access.log");

$line = <access_log>;
$line =~ s/\s+$//;

is($line, 'write', 'log condition is available');

my_http_get('/t2', 'test.com', 8080);

$line = <access_log>;

is($line, undef, 'log env overrides log condition');

my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);
my_http_get('/t3', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 1, "log env plus sample");

my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);
my_http_get('/t4', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 2, "sample in log env");

my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);
my_http_get('/t5', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 1, "override sample in log env");

my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);
my_http_get('/t6', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 5, "sample in log condition");

my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);
my_http_get('/t7', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 2, "override sample in log condition");

my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);
my_http_get('/t8', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 1, "override sample in log condition and log env");

my_http_get('/t9', 'test.com', 8080);

$line = <access_log>;
is ($line, undef, "ordinary variable: set");

my_http_get('/t10', 'test.com', 8080);

$line = <access_log>;
$line =~ s/\s+$//;

is ($line, "write", "ordinary variable: map");

my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);
my_http_get('/t11', 'test.com', 8080);

@lines = <access_log>;
$num = @lines;
is ($num, 1, "ordinary variable plus sample");

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
