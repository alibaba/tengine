#!/usr/bin/perl

# Copyright (C) 2010-2015 Alibaba Group Holding Limited

# Tests that a reload which fails after the configuration was parsed leaves the
# health-check state of the running configuration alone.
#
# The container of checked peers is per configuration, and the module used to
# tell configurations apart by the address of their cycle. A cycle discarded by
# a failed reload is regularly reallocated at the very same address by the next
# reload, so the next configuration was taken for the discarded one: it reused
# the freed container and skipped creating its shared memory zone. Every peer
# lookup on the request path then dereferenced freed memory, and the worker died
# on the first request that picked an upstream peer -- with or without "check"
# configured, since the lookup happens for every peer.
#
# The reload here fails on a bad directive placed after the http{} and stream{}
# blocks: init_main_conf, where the container is registered, has run by then, and
# failing this early leaves the allocator most likely to hand the freed cycle
# back to the next reload. Whether it actually does is up to the allocator, so
# this test can only catch the bug, not prove its absence.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http stream upstream_check/)->plan(8);

my $conf = <<'EOF';

%%TEST_GLOBALS%%

daemon off;
worker_processes 1;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream checked {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=300 rise=1 fall=1 timeout=250 type=http;
        check_http_send "GET / HTTP/1.0\r\n\r\n";
        check_http_expect_alive http_2xx;
    }

    # No "check" here on purpose: the peer lookup runs for unchecked upstreams
    # too, and that is the shape the failure was first seen in.
    upstream unchecked {
        server 127.0.0.1:%%PORT_8081%%;
    }

    server {
        listen      127.0.0.1:%%PORT_8080%%;
        server_name localhost;

        location /checked {
            proxy_pass http://checked/;
        }

        location /unchecked {
            proxy_pass http://unchecked/;
        }

        location /status {
            check_status;
            access_log off;
        }
    }

    server {
        listen      127.0.0.1:%%PORT_8081%%;
        server_name localhost;

        location / {
            return 200 "backend\n";
        }
    }
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream stream_checked {
        server 127.0.0.1:%%PORT_8081%%;

        check interval=300 rise=1 fall=1 timeout=250 type=tcp;
    }

    server {
        listen      127.0.0.1:%%PORT_8090%%;
        proxy_pass  stream_checked;
    }
}

#BAD#

EOF

my $conf_good = $conf;
$conf_good =~ s/#BAD#//;

# The directive sits after both blocks on purpose: the parser reaches it once
# every init_main_conf has run, so the discarded configuration did register its
# container of checked peers before it went away.
my $conf_bad = $conf;
$conf_bad =~ s/#BAD#/this_directive_does_not_exist on;/;

$t->write_file_expand('nginx.conf', $conf_good);
$t->run();

###############################################################################

# Peers start out down and the first probe fires after a random delay of up to
# max(interval, 1s), so wait for the first verdict.
select undef, undef, undef, 2.5;

like(get_status(), qr!^\d+,checked,\S+,up,!m, 'peer up before the reloads');

my $generation = get_generation();

$t->write_file_expand('nginx.conf', $conf_bad);
$t->reload();

# The second reload must not be signalled while the first one is still being
# processed, or it is lost. Kept inline rather than in a helper: a named sub
# closing over $t would keep the object alive until global destruction, where
# its own end-of-test checks can no longer run.
for (1 .. 100) {
	last if $t->read_file('error.log') =~ /unknown directive "this_directive_does_not_exist"/;
	select undef, undef, undef, 0.1;
}

like($t->read_file('error.log'), qr/unknown directive "this_directive_does_not_exist"/,
	'reload failed after both blocks were parsed');

$t->write_file_expand('nginx.conf', $conf_good);
$t->reload();

# Two generations, because the discarded configuration took one with it. This is
# the sensitive assertion: a configuration mistaken for the discarded one never
# creates its zone, so it never bumps the generation either, and one worth of
# progress is exactly what the bug looked like from the outside.
is(wait_for_generation($generation, 10), $generation + 2,
	'both reloads took a generation');

# A zone was created for this configuration, so the status page reports its
# peers rather than an empty list. The failed reload took a generation with it,
# so the "generation - 1" lookup missed and the peers start over from
# default_down -- probing them again is expected here, unlike in
# stream_upstream_check_reload.t where nothing is discarded in between.
ok(wait_for_status(qr!^\d+,checked,\S+,up,!m, 10),
	'http peer up after the reloads');
ok(wait_for_status(qr!^\d+,stream_checked,\S+,up,!m, 10),
	'stream peer up after the reloads');

# The requests below are what used to kill the worker.
like(http_get('/unchecked'), qr/200 OK.*backend/s, 'unchecked upstream serves');
like(http_get('/checked'), qr/200 OK.*backend/s, 'checked upstream serves');
like(stream('127.0.0.1:' . port(8090))->io("GET / HTTP/1.0\r\n\r\n"),
	qr/200 OK/, 'stream upstream serves');

###############################################################################

sub get_status {
	my $r = http_get('/status?format=csv');
	$r =~ s/.*?\x0d\x0a\x0d\x0a//s;
	return $r;
}

sub get_generation {
	my $r = http_get('/status?format=json');
	return $r =~ /"generation":\s*(\d+)/ ? $1 : -1;
}

sub wait_for_status {
	my ($re, $timeout) = @_;

	for (1 .. $timeout * 10) {
		return 1 if get_status() =~ $re;
		select undef, undef, undef, 0.1;
	}

	return 0;
}

sub wait_for_generation {
	my ($previous, $timeout) = @_;
	my $generation;

	for (1 .. $timeout * 10) {
		$generation = get_generation();
		return $generation if $generation > $previous;
		select undef, undef, undef, 0.1;
	}

	return $generation;
}

###############################################################################
