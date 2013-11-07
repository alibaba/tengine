#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for upstream least_conn balancer module.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy upstream_least_conn/)->plan(2);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        least_conn;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, 8081);
$t->run_daemon(\&http_daemon, 8082);
$t->run();

$t->waitforsocket('127.0.0.1:8081');
$t->waitforsocket('127.0.0.1:8082');

###############################################################################

is(many('/', 10), '8081: 5, 8082: 5', 'balanced');
is(parallel('/w', 10), '8081: 1, 8082: 9', 'least conn');

###############################################################################

sub many {
	my ($uri, $count) = @_;
	my %ports;

	for (1 .. $count) {
		if (http_get($uri) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	return join ', ', map { $_ . ": " . $ports{$_} } sort keys %ports;
}

sub parallel {
	my ($uri, $count, %opts) = @_;
	my (@sockets, %ports);

	for (1 .. $count) {
		push(@sockets, http_start($uri));
		select undef, undef, undef, 0.1;
	}

	for (1 .. $count) {
		if (http_end(pop(@sockets)) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	return join ', ', map { $_ . ": " . $ports{$_} } sort keys %ports;
}

sub http_start {
	my ($uri) = @_;

	my $s;
	my $request = "GET $uri HTTP/1.0" . CRLF . CRLF;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(3);
		$s = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1:8080'
		);
		log_out($request);
		$s->print($request);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}
	return $s;
}

sub http_end {
	my ($s) = @_;
	my $reply;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(3);
		local $/;
		$reply = $s->getline();
		log_in($reply);
		alarm(0);
	};
	alarm(0);
	if ($@) {
		log_in("died: $@");
		return undef;
	}
	return $reply;
}

###############################################################################

sub http_daemon {
	my ($port) = @_;

	my $server = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalHost => '127.0.0.1',
		LocalPort => $port,
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

		if ($uri eq '/w' && $port == 8081) {
			Test::Nginx::log_core('||', "$port: sleep(3)");
			select undef, undef, undef, 3;
		}

		Test::Nginx::log_core('||', "$port: response, 200");
		print $client <<EOF;
HTTP/1.1 200 OK
Connection: close
X-Port: $port

OK
EOF

		close $client;
	}
}

###############################################################################
