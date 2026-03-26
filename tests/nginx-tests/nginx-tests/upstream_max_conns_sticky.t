#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams with max_conns feature.

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

my $t = Test::Nginx->new()->has(qw/http proxy upstream_sticky/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u_sticky {
        server 127.0.0.1:8081 route=a;
        server 127.0.0.1:8082 route=b;
        sticky route $arg_route;
    }
    upstream u_sticky_lim {
        server 127.0.0.1:8081 route=a max_conns=2;
        server 127.0.0.1:8082 route=b max_conns=3;
        sticky route $arg_route;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;

        location /sticky {
            proxy_pass http://u_sticky;
        }
        location /sticky_lim {
            proxy_pass http://u_sticky_lim;
        }

        location /close {
            proxy_pass http://127.0.0.1:8085;
        }
    }
}

EOF


$t->run_daemon(\&http_daemon, port(8081), port(8082), port(8085));
$t->try_run('no sticky upstream')->plan(2);

$t->waitforsocket('127.0.0.1:' . port(8081));
$t->waitforsocket('127.0.0.1:' . port(8082));
$t->waitforsocket('127.0.0.1:' . port(8085));

###############################################################################

my ($p1, $p2) = (port(8081), port(8082));

# sticky connections to unlimited peer

is(peers('/sticky?route=a', 4), "$p1 $p1 $p1 $p1", 'sticky');

# sticky connections to limited peer loose persistence and get balanced

is(peers('/sticky_lim?route=a', 6), "$p1 $p1 $p2 $p2 $p2 ", 'sticky limited');

###############################################################################

sub peers {
	my ($uri, $count) = @_;
	my @sockets;

	for (0 .. $count - 1) {
		$sockets[$_] = http_get($uri, start => 1);
		IO::Select->new($sockets[$_])->can_read(1.1);
	}

	http_get('/closeall');

	join ' ', map { http_end($_) =~ /X-Port: (\d+)/ && $1 } (@sockets);
}

###############################################################################

sub http_daemon {
	my (@ports) = @_;
	my (@socks, @clients);

	for my $port (@ports) {
		my $server = IO::Socket::INET->new(
			Proto => 'tcp',
			LocalHost => "127.0.0.1:$port",
			Listen => 5,
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

	push @$saved, $client;
	return 0;
}

###############################################################################
