#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 with proxy module.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::HTTP3;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy cryptx/)
	->has_daemon('openssl')->plan(3)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    log_format test $uri:$status:$request_completion;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        listen       127.0.0.1:8081;
        server_name  localhost;

        access_log %%TESTDIR%%/test.log test;

        location / {
            proxy_pass http://127.0.0.1:8081/stub;
        }

        location /stub {
            limit_rate 100;
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
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('stub', 'SEE-THIS' x 10);
$t->run();

###############################################################################

my ($s, $sid, $frames, $frame);

# upstream check broken connection
# ensure that STOP_SENDING results in write error, checked in a posted event

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream();

select undef, undef, undef, 0.1;
$s->stop_sending($sid, 0x010c);
$frames = $s->read(all => [{ type => 'RESET_STREAM' }]);

($frame) = grep { $_->{type} eq "RESET_STREAM" } @$frames;
ok($frame, 'RESET_STREAM received');

$t->stop();

my $log = $t->read_file('test.log');
like($log, qr|^/:499|, 'client reset connection');
unlike($log, qr|^/stub:200:OK|, 'backend request incomplete');

###############################################################################
