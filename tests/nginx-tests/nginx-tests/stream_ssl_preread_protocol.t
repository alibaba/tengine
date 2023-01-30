#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for stream_ssl_preread module, protocol preread.

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

my $t = Test::Nginx->new()->has(qw/stream stream_ssl_preread stream_return/)
	->write_file_expand('nginx.conf', <<'EOF')->plan(7)->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    server {
        listen       127.0.0.1:8080;
        ssl_preread  on;
        return       $ssl_preread_protocol;
    }
}

EOF

###############################################################################

is(get('SSLv3'), 'SSLv3', 'client hello SSLv3');
is(get('TLSv1'), 'TLSv1', 'client hello TLSv1');
is(get('TLSv1.1'), 'TLSv1.1', 'client hello TLSv1.1');
is(get('TLSv1.2'), 'TLSv1.2', 'client hello TLSv1.2');

is(get_tls13(), 'TLSv1.3', 'client hello supported_versions');

is(get_ssl2('SSLv2'), 'SSLv2', 'client hello version 2');
is(get_ssl2('TLSv1'), 'TLSv1', 'client hello version 2 - TLSv1');

###############################################################################

sub get {
	my $v = shift;
	my ($re, $ch);

	$re = 0x0300, $ch = 0x0300 if $v eq 'SSLv3';
	$re = 0x0301, $ch = 0x0301 if $v eq 'TLSv1';
	$re = 0x0301, $ch = 0x0302 if $v eq 'TLSv1.1';
	$re = 0x0301, $ch = 0x0303 if $v eq 'TLSv1.2';

	my $r = pack("CnNn2C", 0x16, $re, 0x00380100, 0x0034, $ch, 0xeb);
	$r .= pack("N*", 0x6357cdba, 0xa6b8d853, 0xf1f6ac0f);
	$r .= pack("N*", 0xdf03178c, 0x0ae41824, 0xe7643682);
	$r .= pack("N*", 0x3c1b273f, 0xbfde4b00, 0x00000000);
	$r .= pack("CN3", 0x0c, 0x00000008, 0x00060000, 0x03666f6f);

	http($r);
}

sub get_tls13 {
	my $r = pack("N*", 0x16030100, 0x33010000, 0x2f0303eb);
	$r .= pack("N*", 0x6357cdba, 0xa6b8d853, 0xf1f6ac0f);
	$r .= pack("N*", 0xdf03178c, 0x0ae41824, 0xe7643682);
	$r .= pack("N*", 0x3c1b273f, 0xbfde4b00, 0x00000000);
	$r .= pack("CNCn", 0x07, 0x002b0007, 0x02, 0x7f1c);

	http($r);
}

sub get_ssl2 {
	my $v = shift;
	my $ch;

	$ch = 0x0002 if $v eq 'SSLv2';
	$ch = 0x0301 if $v eq 'TLSv1';

	my $r = pack("nCn4", 0x801c, 0x01, $ch, 0x0003, 0x0000, 0x0010);
	$r .= pack("C3", 0x01, 0x00, 0x80);
	$r .= pack("N4", 0x322dd95c, 0x4749ef17, 0x3d5f0916, 0xf0b730f8);

	http($r);
}

###############################################################################
