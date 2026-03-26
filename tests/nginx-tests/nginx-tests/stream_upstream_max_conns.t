#!/usr/bin/perl

# (C) Nginx, Inc.
# (C) Sergey Kandaurov

# Tests for stream upstream module with max_conns feature.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Select;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx qw/ :DEFAULT http_end /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_upstream_least_conn/)
	->has(qw/stream_upstream_hash/)->plan(14);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    upstream u_unlim {
        server 127.0.0.1:8081 max_conns=0;
        server 127.0.0.1:8082;
    }
    upstream u_lim {
        server 127.0.0.1:8081 max_conns=3;
    }

    upstream u_backup {
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 backup;
    }
    upstream u_backup_lim {
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 backup max_conns=3;
    }

    upstream u_two {
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082 max_conns=1;
    }
    upstream u_some {
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082;
    }
    upstream u_many {
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082;
    }

    upstream u_weight {
        server 127.0.0.1:8081 weight=2 max_conns=1;
        server 127.0.0.1:8082;
    }

    upstream u_lc {
        least_conn;
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082;
    }
    upstream u_lc_backup {
        least_conn;
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 backup;
    }
    upstream u_lc_backup_lim {
        least_conn;
        server 127.0.0.1:8081 max_conns=2;
        server 127.0.0.1:8082 backup max_conns=3;
    }

    upstream u_hash {
        hash $remote_addr;
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082 max_conns=2;
    }
    upstream u_chash {
        hash $remote_addr consistent;
        server 127.0.0.1:8081 max_conns=1;
        server 127.0.0.1:8082 max_conns=2;
    }

    server {
        listen      127.0.0.1:8086;
        proxy_pass  u_unlim;
    }

    server {
        listen      127.0.0.1:8087;
        proxy_pass  u_lim;
    }

    server {
        listen      127.0.0.1:8088;
        proxy_pass  u_backup;
    }

    server {
        listen      127.0.0.1:8089;
        proxy_pass  u_backup_lim;
    }

    server {
        listen      127.0.0.1:8090;
        proxy_pass  u_two;
    }

    server {
        listen      127.0.0.1:8091;
        proxy_pass  u_some;
    }

    server {
        listen      127.0.0.1:8092;
        proxy_pass  u_many;
    }

    server {
        listen      127.0.0.1:8093;
        proxy_pass  u_weight;
    }

    server {
        listen      127.0.0.1:8094;
        proxy_pass  u_lc;
    }

    server {
        listen      127.0.0.1:8095;
        proxy_pass  u_lc_backup;
    }

    server {
        listen      127.0.0.1:8096;
        proxy_pass  u_lc_backup_lim;
    }

    server {
        listen      127.0.0.1:8097;
        proxy_pass  u_hash;
    }

    server {
        listen      127.0.0.1:8098;
        proxy_pass  u_chash;
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081), port(8082), port(8085));
$t->run();

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));
$t->waitforsocket('127.0.0.1:' . port(8085));

###############################################################################

my @ports = my ($p1, $p2) = (port(8081), port(8082));

# two peers without max_conns

is(parallel(8086, '/u_unlim?delay=0', 4), "$p1: 2, $p2: 2", 'unlimited');

# reopen connection to test connection subtraction

my @s = http_get_multi(8087, '/u_lim', 2, 1.1);
get(8087, '/close');
push @s, http_get_multi(8087, '/u_lim', 1, 1.1);
get(8085, '/closeall');

is(http_end_multi(\@s), "$p1: 3", 'conn subtraction');

# simple test with limited peer

is(parallel(8087, '/u_lim', 4), "$p1: 3", 'single');

# limited peer with backup peer

is(peers(8088, '/u_backup', 6), "$p1 $p1 $p2 $p2 $p2 $p2", 'backup');

# peer and backup peer, both limited

is(peers(8089, '/u_backup_lim', 6), "$p1 $p1 $p2 $p2 $p2 ", 'backup limited');

# all peers limited

is(parallel(8090, '/u_two', 4), "$p1: 1, $p2: 1", 'all peers');

# subset of peers limited

is(parallel(8091, '/u_some', 4), "$p1: 1, $p2: 3", 'some peers');

# ensure that peer "weight" does not affect its max_conns limit

is(parallel(8093, '/u_weight', 4), "$p1: 1, $p2: 3", 'weight');

# peers with equal server value aggregate max_conns limit

is(parallel(8092, '/u_many', 6), "$p1: 2, $p2: 4", 'equal peer');

# least_conn balancer tests

is(parallel(8094, '/u_lc', 4), "$p1: 1, $p2: 3", 'least_conn');
is(peers(8095, '/u_lc_backup', 6), "$p1 $p1 $p2 $p2 $p2 $p2",
	'least_conn backup');
is(peers(8096, '/u_lc_backup_lim', 6), "$p1 $p1 $p2 $p2 $p2 ",
	'least_conn backup limited');

# hash balancer tests

is(parallel(8097, '/u_hash', 4), "$p1: 1, $p2: 2", 'hash');
is(parallel(8098, '/u_chash', 4), "$p1: 1, $p2: 2", 'hash consistent');

###############################################################################

sub peers {
	my ($port, $uri, $count) = @_;

	my @sockets = http_get_multi($port, $uri, $count, 1.1);
	get(8085, '/closeall');

	join ' ', map { defined $_ && /X-Port: (\d+)/ && $1 }
		map { http_end $_ } (@sockets);
}

sub parallel {
	my ($port, $uri, $count) = @_;

	my @sockets = http_get_multi($port, $uri, $count);
	for (1 .. 20) {
		last if IO::Select->new(@sockets)->can_read(3) == $count;
		select undef, undef, undef, 0.01;
	}
	get(8085, '/closeall');
	return http_end_multi(\@sockets);
}

sub get {
	my ($port, $uri, %opts) = @_;
	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1',
		PeerPort => port($port),
	)
		or die "Can't connect to nginx: $!\n";

	http_get($uri, socket => $s, %opts);
}

sub http_get_multi {
	my ($port, $uri, $count, $wait) = @_;
	my @sockets;

	for (0 .. $count - 1) {
		$sockets[$_] = get($port, $uri, start => 1);
		IO::Select->new($sockets[$_])->can_read($wait) if $wait;
	}

	return @sockets;
}

sub http_end_multi {
	my ($sockets) = @_;
	my %ports;

	for my $sock (@$sockets) {
		my $r = http_end($sock);
		if ($r && $r =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
		close $sock;
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################

sub http_daemon {
	my (@ports) = @_;
	my (@socks, @clients);

	for my $port (@ports) {
		my $server = IO::Socket::INET->new(
			Proto => 'tcp',
			LocalHost => "127.0.0.1:$port",
			Listen => 42,
			Reuse => 1
		)
			or die "Can't create listening socket: $!\n";
		push @socks, $server;
	}

	my $sel = IO::Select->new(@socks);
	my $skip = 4;
	my $count = 0;

	local $SIG{PIPE} = 'IGNORE';

OUTER:
	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if (grep $_ == $fh, @socks) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);
				$count++;

			} else {
				my @busy = grep { $_->sockport() } @ready;

				# finish other handles
				if ($fh->sockport() == port(8085) && @busy > 1
					&& grep $_->sockport() != port(8085),
					@busy)
				{
					next;
				}

				# late events in other handles
				if ($fh->sockport() == port(8085) && @busy == 1
					&& $count > 1 && $skip-- > 0)
				{
					select undef, undef, undef, 0.1;
					next OUTER;
				}

				my $rv = process_socket($fh, \@clients);
				if ($rv == 1) {
					$sel->remove($fh);
					$fh->close;
				}
				if ($rv == 2) {
					for (@clients) {
						$sel->remove($_);
						$_->close;
					}
					$sel->remove($fh);
					$fh->close;
					$skip = 4;
				}
				$count--;
			}
		}
	}
}

# Returns true to close connection

sub process_socket {
	my ($client, $saved) = @_;
	my $port = $client->sockport();

	my $headers = '';
	my $uri = '';

	while (<$client>) {
		$headers .= $_;
		last if (/^\x0d?\x0a?$/);
	}
	return 1 if $headers eq '';

	$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
	return 1 if $uri eq '';

	Test::Nginx::log_core('||', "$port: response, 200");
	print $client <<EOF;
HTTP/1.1 200 OK
X-Port: $port

OK
EOF

	return 2 if $uri =~ /closeall/;
	return 1 if $uri =~ /close/;

	push @$saved, $client;
	return 0;
}

###############################################################################
