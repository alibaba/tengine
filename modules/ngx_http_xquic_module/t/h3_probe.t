#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Probe: can the upstream pure-Perl HTTP/3 client drive the xquic listener?
#
# Tengine implements HTTP/3 with xquic rather than the native nginx QUIC
# stack, so the generic h3_*.t cases inherited from upstream all skip here:
# they ask for has(http_v3), which matches nothing in our configure
# arguments.  Those cases are worth having -- they assert HTTP/3 protocol
# semantics that any conforming implementation owes, not native-stack
# internals -- but porting thirteen of them is only worth starting if the
# upstream client can talk to xquic at all.
#
# That is the single question this file answers: does Test::Nginx::HTTP3
# complete a QUIC handshake against an xquic listener and exchange one
# HTTP/3 request?  If it does, the generic cases can be ported by swapping
# "listen ... quic" for the xquic directives used below.  If it does not,
# the failure recorded here says how far the exchange got, and HTTP/3
# coverage stays with xquic's own test_client and test/*.py suites.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib '../../../tests/nginx-tests/nginx-tests/lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

# has('xquic') falls through to the literal-regex branch of has_module() and
# matches "--add-module=modules/ngx_http_xquic_module" in the configure
# arguments; 'cryptx' gates on the CryptX modules Test::Nginx::HTTP3 needs.
#
# todo_alerts(): see the longer note in ngx_http_xquic.t -- running xquic at
# all emits [alert]s that say nothing about this test, namely
# setsockopt(new-udp-hash) on non-Alibaba kernels at startup and "open
# socket left in connection" on shutdown.

my $t = Test::Nginx->new()->has(qw/http xquic cryptx/)
	->has_daemon('openssl')
	->todo_alerts()
	->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

xquic_log   logs/xquic.log debug;

http {
    %%TEST_GLOBALS_HTTP%%

    xquic_ssl_certificate        %%TESTDIR%%/localhost.crt;
    xquic_ssl_certificate_key    %%TESTDIR%%/localhost.key;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% xquic;
        server_name  localhost;

        ssl_certificate        %%TESTDIR%%/localhost.crt;
        ssl_certificate_key    %%TESTDIR%%/localhost.key;

        location / {
            return 200 "SEE-THIS\n";
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config '$d/openssl.conf' -subj '/CN=$name/' "
		. "-out '$d/$name.crt' -keyout '$d/$name.key' "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

# The xquic key is read by the worker after privilege drop, so it has to stay
# readable there; see the note in ngx_http_xquic_module about workers exiting
# with a fatal code when it is not.
chmod 0644, "$d/localhost.key";

$t->run();

###############################################################################

# Test 1 -- handshake.  new() dies on a failed handshake, so trap it and keep
# the reason: it is the whole point of this probe.

my $s = eval { Test::Nginx::HTTP3->new() };
my $err = $@;

ok($s, 'QUIC handshake against xquic')
	or diag("handshake failed: $err");

SKIP: {
	skip 'no QUIC handshake against xquic', 2 unless $s;

	my $sid = $s->new_stream({ path => '/' });
	my $frames = eval { $s->read(all => [{ sid => $sid, fin => 1 }]) } || [];
	diag("read failed: $@") if $@;

	my ($header) = grep { $_->{type} eq "HEADERS" } @$frames;
	is($header->{headers}->{':status'}, 200, 'HTTP/3 response status');

	my ($data) = grep { $_->{type} eq "DATA" } @$frames;
	like($data->{data}, qr/SEE-THIS/, 'HTTP/3 response body');
}

###############################################################################
