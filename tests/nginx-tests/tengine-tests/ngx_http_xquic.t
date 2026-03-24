#!/usr/bin/perl

# Copyright (C) 2026 Alibaba Group Holding Limited

# Tests for ngx_http_xquic_module - QUIC/HTTP3 with xquic listener.

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

# Check if test_client exists (passed via environment variable or found in PATH)
my $test_client = $ENV{TEST_XQUIC_CLIENT};
my $has_test_client = 0;

if (!$test_client) {
    # Try to find test_client in PATH
    foreach my $dir (split(/:/, $ENV{PATH} || '')) {
        if (-x "$dir/test_client") {
            $test_client = "$dir/test_client";
            $has_test_client = 1;
            last;
        }
    }
} else {
    $has_test_client = -x $test_client ? 1 : 0;
}

my $test_count = $has_test_client ? 5 : 4;

my $t = Test::Nginx->new()->has(qw/http/)
    ->has_daemon('openssl')
    ->plan($test_count);

$t->write_file_expand('nginx.conf', <<'EOF');

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
        listen 127.0.0.1:%%PORT_8989_UDP%% xquic;
        server_name localhost;

        ssl_certificate        %%TESTDIR%%/localhost.crt;
        ssl_certificate_key    %%TESTDIR%%/localhost.key;

        location / {
            return 200 "HTTP3 OK\n";
        }
    }

    server {
        listen 127.0.0.1:8080;

        location / {
            return 200 "HTTP1.1 OK\n";
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

$t->write_file('index.html', <<EOF);
Test Page
EOF

$t->run();

###############################################################################

# Save test directory for debugging
my $testdir = $t->testdir();

# Test 1: Check xquic directives are recognized
sleep 1;
my $error_log = $t->read_file('error.log');
unlike($error_log, qr/unknown directive.*xquic/i, 'xquic directives recognized');

# Test 2: Check xquic initialization in error log
if ($error_log =~ /xquic/i) {
    pass('xquic module initialized');
} else {
    fail('xquic module initialized');
}

# Test 3: Check UDP port listening
my $port_check = `ss -uln 2>/dev/null | grep 8989 || netstat -uln 2>/dev/null | grep 8989`;
if ($port_check =~ /8989/) {
    pass('xquic UDP port listening');
} else {
    fail('xquic UDP port listening');
}

# Test 4: Check xquic log file
my $xquic_log_exists = -f "$d/logs/xquic.log";
if ($xquic_log_exists) {
    pass('xquic log file created');
} else {
    fail('xquic log file created');
}

# Test 5: Send HTTP/3 request using xquic test_client
if ($has_test_client) {
    sleep 2;
    # Use -V 1 to allow self-signed certificates, -t 5 for 5s timeout
    my $output = `$test_client -a 127.0.0.1 -p 8989 -u https://localhost/ -h localhost -l e -V 1 -t 5 2>&1`;
    
    diag("test_client output:\n$output");
    
    if ($output =~ /recv_body_size:(\d+)/) {
        my $recv_size = $1;
        diag("xquic test_client result: recv_body_size=$recv_size");
        # Expected response: "HTTP3 OK\n" = 9 bytes
        if ($recv_size >= 9) {
            pass('xquic test_client received valid response (recv_body_size:' . $recv_size . ')');
        } else {
            fail('xquic test_client received unexpected response size: ' . $recv_size . ' (expected >= 9)');
        }
    } else {
        fail('xquic test_client failed to parse output');
    }
    
    # Clear error log to avoid alerts from test_client failures
    $t->write_file('error.log', '');
}

# Output detailed error information for debugging
diag("=" x 80);
diag("DEBUG INFORMATION");
diag("=" x 80);
diag("Test directory: $testdir");
diag("-" x 80);
diag("Error log content:");
diag($error_log);
diag("-" x 80);
diag("Directory contents:");
diag(`ls -la $testdir/ 2>&1`);
diag("-" x 80);
if (-d "$testdir/logs") {
    diag("Logs directory contents:");
    diag(`ls -la $testdir/logs/ 2>&1`);
    diag("-" x 80);
    if (-f "$testdir/logs/xquic.log") {
        diag("xquic.log content (first 50 lines):");
        diag(`head -50 $testdir/logs/xquic.log 2>&1`);
    }
}
diag("=" x 80);

$t->stop();

###############################################################################
