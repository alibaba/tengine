#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for HTTP/3 protocol with limit_req.

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

my $t = Test::Nginx->new()->has(qw/http http_v3 proxy limit_req cryptx/)
	->has_daemon('openssl')->plan(6);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    limit_req_zone   $binary_remote_addr  zone=req:1m rate=1r/s;

    log_format test $status;

    server {
        listen       127.0.0.1:%%PORT_8980_UDP%% quic;
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            add_header X-Body $request_body;
            add_header X-Body-File $request_body_file;
            client_body_in_file_only on;
            proxy_pass http://127.0.0.1:8081/stub;
            limit_req  zone=req burst=2;
            access_log %%TESTDIR%%/test.log test;
        }

        location /stub { }
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

$t->write_file('stub', '');
$t->run();

###############################################################################

# request body delayed in limit_req

my $s = Test::Nginx::HTTP3->new();
my $sid = $s->new_stream({ path => '/', body_more => 1 });
$s->h3_body('TEST', $sid);
my $frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

my ($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST',
	'request body - limit req');

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/', body_more => 1 });
select undef, undef, undef, 1.1;
$s->h3_body('TEST', $sid);
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST',
	'request body - limit req - limited');

# request body with request

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/', body => 'TEST2' });
select undef, undef, undef, 1.1;
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is(read_body_file($frame->{headers}->{'x-body-file'}), 'TEST2',
	'request body - limit req - with headers');

# delayed with an empty DATA frame

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/', body_more => 1 });
$s->h3_body('', $sid);
select undef, undef, undef, 1.1;
$frames = $s->read(all => [{ sid => $sid, fin => 1 }]);

($frame) = grep { $_->{type} eq "HEADERS" } @$frames;
is($frame->{headers}->{':status'}, 200, 'request body - limit req - empty');

# detect RESET_STREAM while request is delayed

$s = Test::Nginx::HTTP3->new();
$sid = $s->new_stream({ path => '/', body_more => 1 });
wait_ack($s);

$s->reset_stream($sid, 0x010c);
$frames = $s->read(all => [{ type => 'DECODER_C' }]);

($frame) = grep { $_->{type} eq "DECODER_C" } @$frames;
is($frame->{'val'}, $sid, 'reset stream - cancellation');

$t->stop();

like($t->read_file('test.log'), qr/499/, 'reset stream - log');

###############################################################################

sub wait_ack {
	my ($s) = @_;
	my $last = $s->{pn}[0][3];

	for (1 .. 5) {
		my $frames = $s->read(all => [ {type => 'ACK' }]);
		my ($frame) = grep { $_->{type} eq "ACK" } @$frames;
		last unless $frame->{largest} < $last;
	}
}

sub read_body_file {
	my ($path) = @_;
	return unless $path;
	open FILE, $path or return "$!";
	local $/;
	my $content = <FILE>;
	close FILE;
	return $content;
}

###############################################################################
