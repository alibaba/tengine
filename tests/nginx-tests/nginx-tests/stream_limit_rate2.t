#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for stream proxy module, limit rate directives, variables support.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_map/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    # download and upload rates are set equal to the maximum
    # number of bytes transmitted

    # proxy_download_rate value comes from following calculations:
    # test string length (1000) + whitespace (1) + time string length (10)

    map $server_port $down {
        default        1011;
        %%PORT_8082%%  0;
        %%PORT_8083%%  1;
        %%PORT_8085%%  250;
    }

    map $server_port $up {
        default        1000;
        %%PORT_8082%%  0;
        %%PORT_8084%%  1;
        %%PORT_8086%%  250;
    }

    proxy_download_rate      $down;
    proxy_upload_rate        $up;

    server {
        listen               127.0.0.1:8081;
        proxy_pass           127.0.0.1:8080;
    }

    server {
        listen               127.0.0.1:8082;
        proxy_pass           127.0.0.1:8080;
        proxy_download_rate  $down;
        proxy_upload_rate    $up;
    }

    server {
        listen               127.0.0.1:8083;
        proxy_pass           127.0.0.1:8080;
        proxy_download_rate  $down;
    }

    server {
        listen               127.0.0.1:8084;
        proxy_pass           127.0.0.1:8080;
        proxy_upload_rate    $up;
    }

    server {
        listen               127.0.0.1:8085;
        proxy_pass           127.0.0.1:8080;
        proxy_download_rate  $down;
    }

    server {
        listen               127.0.0.1:8086;
        proxy_pass           127.0.0.1:8087;
        proxy_upload_rate    $up;
    }
}

EOF

$t->run_daemon(\&stream_daemon, port(8080));
$t->run_daemon(\&stream_daemon, port(8087));
$t->run()->plan(9);

$t->waitforsocket('127.0.0.1:' . port(8080));
$t->waitforsocket('127.0.0.1:' . port(8087));

###############################################################################

my $str = '1234567890' x 100;

my %r = response($str, peer => '127.0.0.1:' . port(8081));
is($r{'data'}, $str, 'exact limit');

%r = response($str . 'extra', peer => '127.0.0.1:' . port(8082));
is($r{'data'}, $str . 'extra', 'unlimited');

SKIP: {
skip 'unsafe on VM', 3 unless $ENV{TEST_NGINX_UNSAFE};

# if interaction between backend and client is slow then proxy can add extra
# bytes to upload/download data

%r = response($str . 'extra', peer => '127.0.0.1:' . port(8081));
is($r{'data'}, $str, 'limited');

%r = response($str, peer => '127.0.0.1:' . port(8083), readonce => 1);
is($r{'data'}, '1', 'download - one byte');

%r = response($str, peer =>  '127.0.0.1:' . port(8084));
is($r{'data'}, '1', 'upload - one byte');

}

# Five chunks are split with four 1s delays:
# the first four chunks are quarters of test string
# and the fifth one is some extra data from backend.

%r = response($str, peer =>  '127.0.0.1:' . port(8085));
my $diff = time() - $r{'time'};
cmp_ok($diff, '>=', 4, 'download - time');
is($r{'data'}, $str, 'download - data');

my $time = time();
%r = response($str . 'close', peer => '127.0.0.1:' . port(8086));
$diff = time() - $time;
cmp_ok($diff, '>=', 4, 'upload - time');
is($r{'data'}, $str . 'close', 'upload - data');

###############################################################################

sub response {
	my ($data, %extra) = @_;

	my $s = stream($extra{peer});
	$s->write($data);

	$data = '';
	while (1) {
		my $buf = $s->read();
		last unless length($buf);

		$data .= $buf;

		last if $extra{'readonce'};
	}
	$data =~ /([\S]*)\s?(\d+)?/;

	return ('data' => $1, 'time' => $2)
}

###############################################################################

sub stream_daemon {
	my $port = shift;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Listen => 5,
		Reuse => 1
	)
		or die "Can't create listening socket: $!\n";

	my $sel = IO::Select->new($server);

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if ($server == $fh) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (stream_handle_client($fh)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

sub stream_handle_client {
	my ($client) = @_;

	log2c("(new connection $client)");

	$client->sysread(my $buffer, 65536) or return 1;

	log2i("$client $buffer");

	$buffer .= " " . time() if $client->sockport() eq port(8080);

	log2o("$client $buffer");

	$client->syswrite($buffer);

	return $client->sockport() eq port(8080) ? 1 : $buffer =~ /close/;
}

sub log2i { Test::Nginx::log_core('|| <<', @_); }
sub log2o { Test::Nginx::log_core('|| >>', @_); }
sub log2c { Test::Nginx::log_core('||', @_); }

###############################################################################
