#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for debug_connection with syslog.

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

my $t = Test::Nginx->new()->has(qw/http --with-debug ipv6 proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
    debug_connection ::1;
}

http {
    %%TEST_GLOBALS_HTTP%%

    error_log syslog:server=127.0.0.1:8080 alert;
    error_log syslog:server=127.0.0.1:8081 alert;

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:8080;
        server_name  localhost;

        location /debug {
            proxy_pass http://[::1]:8080/;
        }
    }
}

EOF

eval {
	open OLDERR, ">&", \*STDERR; close STDERR;
	$t->run();
	open STDERR, ">&", \*OLDERR;
};
plan(skip_all => 'no inet6 support') if $@;

$t->plan(5);

###############################################################################

is(get_syslog('/', 8080), '', 'no debug_connection syslog 1');
is(get_syslog('/', 8081), '', 'no debug_connection syslog 2');

my @msgs = get_syslog('/debug', 8080, 8081);
like($msgs[0], qr/\[debug\]/, 'debug_connection syslog 1');
like($msgs[1], qr/\[debug\]/, 'debug_connection syslog 2');
is($msgs[0], $msgs[1], 'debug_connection syslog1 syslog2 match');

###############################################################################

sub get_syslog {
	my ($uri, @port) = @_;
	my (@s);
	my $rfd = '';
	my @data;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(1);
		map {
			push @s, IO::Socket::INET->new(
				Proto => 'udp',
				LocalAddr => "127.0.0.1:$_"
			);
		} (@port);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}

	http_get($uri);

	map {
		my $data = '';
		vec($rfd, fileno($_), 1) = 1;
		select $rfd, undef, undef, 1;
		while (select($rfd, undef, undef, 0.1) > 0
			&& vec($rfd, fileno($_), 1))
		{
			my ($buffer);
			sysread($_, $buffer, 4096);
			$data .= $buffer;
		}
		push @data, $data;
		$_->close();
	} (@s);

	return $data[0] if scalar @data == 1;
	return @data;
}

###############################################################################
