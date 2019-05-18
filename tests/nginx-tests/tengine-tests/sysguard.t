#!/usr/bin/perl

###############################################################################

use warnings;
use strict;

use Test::More;
use File::Copy;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Time::Parse;


###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;
my $can_use_threads = eval 'use threads; 1';

plan(skip_all => 'perl does not support threads') if (!$can_use_threads || threads->VERSION < 1.86);
plan(skip_all => 'unsupported os') if (!(-e "/usr/bin/uptime" || -e "/usr/bin/free"));

my $t = Test::Nginx->new()->has(qw/http sysguard/)->plan(26);

$t->set_dso("ngx_http_fastcgi_module", "ngx_http_fastcgi_module.so");
$t->set_dso("ngx_http_uwsgi_module", "ngx_http_uwsgi_module.so");
$t->set_dso("ngx_http_scgi_module", "ngx_http_scgi_module.so");

my $content = <<'EOF';

%%TEST_GLOBALS%%

master_process off;
daemon         off;

%%TEST_GLOBALS_DSO%%

events {
}

http {
    %%TEST_GLOBALS_HTTP%%
    access_log    off;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        sysguard on;

        location /load_limit {
            root %%TESTDIR%%;
            sysguard_load load=%%load1%% action=/limit;
        }

        location /load_unlimit {
            root %%TESTDIR%%;
            sysguard_load load=%%load2%% action=/limit;
        }

        location /cpu_limit {
            root %%TESTDIR%%;
            sysguard_cpu usage=%%cpu1%% period=1s action=/limit;
        }

        location /cpu_unlimit {
            root %%TESTDIR%%;
            sysguard_cpu usage=%%cpu2%% period=1s action=/limit;
        }

        location /free_unlimit {
            root %%TESTDIR%%;
            sysguard_mem free=%%free1%%k action=/limit;
        }

        location /free_limit {
            root %%TESTDIR%%;
            #error_log %%TESTDIR%%/free_limit.log debug;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /mem_load_limit {
            root %%TESTDIR%%;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /mem_load_limit1 {
            root %%TESTDIR%%;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /mem_load_limit2 {
            root %%TESTDIR%%;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_mem free=%%free1%%k action=/limit;
        }

        location /mem_load_limit3  {
            root %%TESTDIR%%;
            #error_log %%TESTDIR%%/error_mem_load_limit3.log debug;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_mem free=%%free1%%k action=/limit;
        }

        location /mem_cpu_limit {
            root %%TESTDIR%%;
            sysguard_cpu usage=%%cpu2%% action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /mem_cpu_limit1 {
            root %%TESTDIR%%;
            sysguard_cpu usage=%%cpu1%% action=/limit;
            sysguard_mem free=%%free1%%k action=/limit;
        }

        location /mem_cpu_limit2 {
            root %%TESTDIR%%;
            sysguard_cpu usage=%%cpu2%% action=/limit;
            sysguard_mem free=%%free1%%k action=/limit;
        }


        location /rt_limit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_rt rt=0.001 period=2s action=/limit;
        }

        location /load_and_rt_limit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_rt rt=0.001 period=2s action=/limit;
        }

        location /load_or_rt_limit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode or;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_rt rt=0.001 period=2s actoin=/limit;
        }

        location /load_or_rt_limit1 {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode or;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_rt rt=0.001 period=2s actoin=/limit;
        }

        location /load_or_rt_limit2 {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode or;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_rt rt=10.000 period=2s actoin=/limit;
        }

        location /rt_unlimit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_rt rt=10.000 period=1s action=/limit;
        }

        location /load_and_rt_unlimit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_rt rt=10.000 period=1s action=/limit;
        }

        location /load_and_rt_unlimit1 {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_rt rt=10.000 period=1s action=/limit;
        }

        location /load_and_rt_unlimit2 {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_rt rt=0.001 period=1s action=/limit;
        }

        location /load_or_rt_unlimit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode or;
            sysguard_load load=%%load2%% action=/limit;
            sysguard_rt rt=10.000 period=1s action=/limit;
        }

        location /load_and_mem_and_rt_limit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_load load=%%load1%% action=/limit;
            sysguard_rt rt=0.001 period=2s action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /cpu_and_mem_limit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_cpu usage=%%cpu1%% action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }

        location /cpu_and_mem_unlimit {
            proxy_pass http://127.0.0.1:8081;
            sysguard_mode and;
            sysguard_cpu usage=%%cpu2%% action=/limit;
            sysguard_mem free=%%free2%%k action=/limit;
        }


        location /limit {
            return 503;
        }
    }
}

EOF


my $pload = getload($t);
warn "pload:".($pload);
runload();
my $load = getload($t);
warn "load:".($load);

my $load_less = $load - 10.0;
if ($load_less lt 2) {
    $load_less = 0;
}
warn "load_less:".($load_less);

my $load_up= $load + 10.0;
warn "load_up:".($load_up);

my $cpu = getcpu();
my $cpu_less = int($cpu - 10);
if ($cpu_less < 2) {
    $cpu_less = 0;
}

my $cpu_up = int($cpu + 10);
if ($cpu_up > 100) {
    $cpu_up = 100;
}
warn "cpu:".$cpu;
warn "cpu_less:".$cpu_less;
warn "cpu_up:".$cpu_up;

my $free = getfree($t);
warn "free:".($free);

my $free_less = $free - 100000;
warn "free_less:".($free_less);

my $free_up = $free + 100000;
warn "free_up:".($free_up);

$content =~ s/%%load1%%/$load_less/gmse;
$content =~ s/%%cpu1%%/$cpu_less/gmse;
$content =~ s/%%cpu2%%/$cpu_up/gmse;
$content =~ s/%%load2%%/$load_up/gmse;
$content =~ s/%%free1%%/$free_less/gmse;
$content =~ s/%%free2%%/$free_up/gmse;

$t->write_file_expand('nginx.conf', $content);

$t->run_daemon(\&http_daemon);
$t->run();

###############################################################################

like(http_get("/load_limit"), qr/503/, 'load_limit');


like(http_get("/load_unlimit"), qr/404/, 'load_unlimit');

http_get("/cpu_limit");
# To expire cache (sysguard interval)
sleep 2;
http_get("/cpu_limit");
sleep 2;
like(http_get("/cpu_limit"), qr/503/, 'cpu_limit');

http_get("/cpu_unlimit");
# To expire cache (sysguard interval)
sleep 2;
http_get("/cpu_unlimit");
sleep 2;
like(http_get("/cpu_unlimit"), qr/404/, 'cpu_unlimit');

like(http_get("/free_unlimit"), qr/404/, 'free_unlimit');
like(http_get("/free_limit"), qr/503/, 'free_limit');

like(http_get("/mem_load_limit"), qr/503/, 'mem_load_limit');
like(http_get("/mem_load_limit1"), qr/503/, 'mem_load_limit1');
like(http_get("/mem_load_limit2"), qr/503/, 'mem_load_limit2');
like(http_get("/mem_load_limit3"), qr/404/, 'mem_load_limit3');


like(http_get("/mem_cpu_limit"), qr/503/, 'mem_cpu_limit');
http_get("/mem_cpu_limit1");
sleep 2;
http_get("/mem_cpu_limit1");
sleep 2;
like(http_get("/mem_cpu_limit1"), qr/503/, 'mem_cpu_limit1');
like(http_get("/mem_cpu_limit2"), qr/404/, 'mem_cpu_limit2');

http_get("/rt_limit");
# To expire cache (sysguard interval)
sleep 1;

like(http_get("/rt_limit"), qr/503/, 'rt_limit');

http_get("/load_and_rt_limit");
sleep 1;
like(http_get("/load_and_rt_limit"), qr/503/, 'load_and_rt_limit');
http_get("/load_or_rt_limit");
sleep 1;
like(http_get("/load_or_rt_limit"), qr/503/, 'load_or_rt_limit');
like(http_get("/load_or_rt_limit1"), qr/503/, 'load_or_rt_limit1');
like(http_get("/load_or_rt_limit2"), qr/503/, 'load_or_rt_limit2');

sleep 1;
http_get("/rt_unlimit");
like(http_get("/rt_unlimit"), qr/404/, 'rt_unlimit');

like(http_get("/load_and_rt_unlimit"), qr/404/, 'load_and_rt_unlimit');
like(http_get("/load_and_rt_unlimit1"), qr/404/, 'load_and_rt_unlimit1');
like(http_get("/load_and_rt_unlimit2"), qr/404/, 'load_and_rt_unlimit2');
like(http_get("/load_or_rt_unlimit"), qr/404/, 'load_or_rt_unlimit');

sleep 1;
http_get("/load_and_mem_and_rt_limit");
sleep 1;
like(http_get("/load_and_mem_and_rt_limit"), qr/503/,
     'load_and_mem_and_rt_limit');

http_get("/cpu_and_mem_limit");
sleep 2;
http_get("/cpu_and_mem_limit");
sleep 2;
like(http_get("/cpu_and_mem_limit"), qr/503/, 'cpu_and_mem_limit');

http_get("/cpu_and_mem_unlimit");
sleep 2;
http_get("/cpu_and_mem_unlimit");
sleep 2;
like(http_get("/cpu_and_mem_unlimit"), qr/404/, 'cpu_and_mem_unlimit');


closeload();

sub getload
{
    my($t) = @_;
    system("cat /proc/loadavg | awk  '{print \$1}' > $t->{_testdir}/uptime");
    open(FD, "$t->{_testdir}/uptime")||die("Can not open the file!$!n");
    my $uptime=<FD>;
    close(FD);

    return $uptime;
}

sub getfree
{
    my($t) = @_;
    #system("/usr/bin/free | grep Mem | awk '{print \$4 + \$6 + \$7}' > $t->{_testdir}/free");
    #
open(my $meminfo, "/proc/meminfo") or die("Can't open proc meminfo");
my $cache;
my $buffer;
my $memfree;
while(my $line = <$meminfo>) {
    if ($line =~ /^Cached:\s+(\d+)\skB$/) {
        $cache = $1;
    }

    if ($line =~ /^Buffers:\s+(\d+)\skB$/) {
        $buffer = $1;
    }

    if ($line =~ /^MemFree:\s+(\d+)\skB$/) {
        $memfree = $1;
    }
}
#
    my $freeall = $cache + $buffer + $memfree;

    return $freeall;
}

sub while_thread
{
    $SIG{'KILL'} = sub { threads->exit(); };
    my $j = 0;
    my $i = 0;
    for ($i = 0; $i<=1000000000; $i++) {
        $j = $j + 1;
    }
}

our @ths;

sub runload
{
    my $i = 0;
    for ($i = 0; $i<=64; $i++) {
        $ths[$i] = threads->create( \&while_thread);
    }

    sleep(60);
}

sub closeload
{
    my $i = 0;
    for ($i = 0; $i<=64; $i++) {
        $ths[$i]->kill('KILL')->detach();
    }
}

sub getcpu
{
    my $SLEEPTIME = 1;

    if (-e "/tmp/stat") {
        unlink "/tmp/stat";
    }
    my $JIFF_TMP;
    open (JIFF_TMP, ">>/tmp/stat") || die "Can't open /proc/stat file!\n";
    my $JIFF;
    open (JIFF, "/proc/stat") || die "Can't open /proc/stat file!\n";
    my @jiff_0=<JIFF>;
    print JIFF_TMP $jiff_0[0];
    close (JIFF);

    sleep $SLEEPTIME;

    open (JIFF, "/proc/stat") || die "Can't open /proc/stat file!\n";
    my @jiff_1=<JIFF>;
    print JIFF_TMP $jiff_1[0];
    close (JIFF);
    close (JIFF_TMP);

    my @USER = `awk '{print \$2}' "/tmp/stat"`;
    my @NICE = `awk '{print \$3}' "/tmp/stat"`;
    my @SYSTEM = `awk '{print \$4}' "/tmp/stat"`;
    my @IDLE = `awk '{print \$5}' "/tmp/stat"`;
    my @IOWAIT = `awk '{print \$6}' "/tmp/stat"`;
    my @IRQ = `awk '{print \$7}' "/tmp/stat"`;
    my @SOFTIRQ = `awk '{print \$8}' "/tmp/stat"`;

    my $JIFF_0 = $USER[0] + $NICE[0] + $SYSTEM[0] + $IDLE[0] + $IOWAIT[0] + $IRQ[0] + $SOFTIRQ[0];
    my $JIFF_1 = $USER[1] + $NICE[1] + $SYSTEM[1] + $IDLE[1] + $IOWAIT[1] + $IRQ[1] + $SOFTIRQ[1];

    my $SYS_USAGE = (($USER[0] + $NICE[0] + $SYSTEM[0]) - ($USER[1] + $NICE[1] + $SYSTEM[1])) * 100 / ($JIFF_0 - $JIFF_1);

    return $SYS_USAGE;
}

sub http_daemon {
    my $server = IO::Socket::INET->new(
        Proto => 'tcp',
        LocalHost => '127.0.0.1:8081',
        Listen => 5,
        Reuse => 1
    )
    or die "Can't create listening socket: $!\n";

    local $SIG{PIPE} = 'IGNORE';

    while (my $client = $server->accept()) {
        $client->autoflush(1);

        my $headers = '';
        my $uri = '';

        while (<$client>) {
            $headers .= $_;
            last if (/^\x0d?\x0a?$/);
        }

        $uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;

        if ($uri =~ /^.*_limit$/) {
            sleep 1;
            print $client <<'EOF';
HTTP/1.1 200 OK
Connection: close

EOF
            print $client "TEST-OK-IF-YOU-SEE-THIS"
            unless $headers =~ /^HEAD/i;

        } else {

            print $client <<"EOF";
HTTP/1.1 404 Not Found
Connection: close

Oops, '$uri' not found
EOF
        }

        close $client;
    }
}
