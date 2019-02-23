#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for debug_connection with syslog.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http --with-debug proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
    debug_connection ::1;
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_log syslog:server=127.0.0.1:%%PORT_8981_UDP%% alert;
    error_log syslog:server=127.0.0.1:%%PORT_8982_UDP%% alert;

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location /debug {
            proxy_pass http://[::1]:%%PORT_8080%%/;
        }
    }
}

EOF

$t->try_run('no inet6 support')->plan(5);

###############################################################################

my ($s1, $s2) = map {
	IO::Socket::INET->new(
		Proto => 'udp',
		LocalAddr => "127.0.0.1:$_"
	)
		or die "Can't open syslog socket $_: $!";
} port(8981), port(8982);

is(get_syslog('/', $s1), '', 'no debug_connection syslog 1');
is(get_syslog('/', $s2), '', 'no debug_connection syslog 2');

my @msgs = get_syslog('/debug', $s1, $s2);
like($msgs[0], qr/\[debug\]/, 'debug_connection syslog 1');
like($msgs[1], qr/\[debug\]/, 'debug_connection syslog 2');
is($msgs[0], $msgs[1], 'debug_connection syslog1 syslog2 match');

###############################################################################

sub get_syslog {
	my ($uri, @s) = @_;
	my @data;

	http_get($uri);

	map {
		my $data = '';
		IO::Select->new($_)->can_read(1);
		while (IO::Select->new($_)->can_read(0.1)) {
			my ($buffer);
			sysread($_, $buffer, 4096);
			$data .= $buffer;
		}
		push @data, $data;
	} (@s);

	return $data[0] if scalar @data == 1;
	return @data;
}

###############################################################################
