#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for upstream hash balancer module.

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

my $t = Test::Nginx->new()->has(qw/http proxy rewrite upstream_hash/)->plan(15);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    upstream u {
        hash $arg_a;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
    }

    upstream u2 {
        hash $arg_a;
        server 127.0.0.1:8081;
        server 127.0.0.1:8083;
    }

    upstream cw {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 weight=10;
    }

    upstream cw2 {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8083 weight=10;
    }

    upstream c {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
    }

    upstream c2 {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8083;
    }

    upstream bad {
        hash $arg_a;
        server 127.0.0.1:8081;
        server 127.0.0.1:8084;
    }

    upstream cbad {
        hash $arg_a consistent;
        server 127.0.0.1:8081;
        server 127.0.0.1:8084;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass http://u;
        }
        location /2 {
            proxy_pass http://u2;
        }
        location /cw {
            proxy_pass http://cw;
        }
        location /cw2 {
            proxy_pass http://cw2;
        }
        location /c {
            proxy_pass http://c;
        }
        location /c2 {
            proxy_pass http://c2;
        }
        location /bad {
            proxy_pass http://bad;
        }
        location /cbad {
            proxy_pass http://cbad;
        }
        location /busy {
            proxy_pass http://bad/busy;
            add_header X-IP $upstream_addr always;
        }
        location /cbusy {
            proxy_pass http://cbad/busy;
            add_header X-IP $upstream_addr always;
        }
        location /pnu {
            proxy_pass http://u/;
            proxy_next_upstream http_502;
        }
    }

    server {
        listen       127.0.0.1:8081;
        listen       127.0.0.1:8082;
        listen       127.0.0.1:8083;
        server_name  localhost;

        add_header X-Port $server_port;

        location / {
            return 204;
        }

        location /502 {
            if ($server_port = %%PORT_8083%%) {
                return 502;
            }
            return 204;
        }

        location /busy {
            return 444;
        }
    }

    server {
        listen       127.0.0.1:8084;
        server_name  localhost;
        return 444;
    }
}

EOF

$t->run();

###############################################################################

my @ports = my ($p1, $p2, $p3) = (port(8081), port(8082), port(8083));

# Only requests for absent peer are moved to other peers if hash is consistent.
# Check this by comparing two upstreams with different number of peers.

ok(!cmp_peers([iter('/', 20)], [iter('/2', 20)], $p2), 'inconsistent');
ok(cmp_peers([iter('/c', 20)], [iter('/c2', 20)], $p2), 'consistent');
ok(cmp_peers([iter('/cw', 20)], [iter('/cw2', 20)], $p2), 'consistent weight');

like(many('/?a=1', 10), qr/($p1|$p2|$p3): 10/, 'stable hash');
like(many('/c?a=1', 10), qr/($p1|$p2|$p3): 10/, 'stable hash - consistent');

# fallback to round-robin

like(many('/?a=', 6), qr/$p1: 2, $p2: 2, $p3: 2/, 'empty key');
like(many('/c?a=', 6), qr/$p1: 2, $p2: 2, $p3: 2/, 'empty key - consistent');

my @res = iter('/', 10);

is(@res, 10, 'all hashed peers');

@res = grep { $_ != $p3 } @res;
my @res2 = iter('/502', 10);

is_deeply(\@res, \@res2, 'no proxy_next_upstream');
isnt(@res2, 10, 'no proxy_next_upstream peers');

is(iter('/pnu/502', 10), 10, 'proxy_next_upstream peers');

@res = grep { $_ == $p1 } iter('/bad', 20);
is(@res, 20, 'all hashed peers - bad');

@res = grep { $_ == $p1 } iter('/cbad', 20);
is(@res, 20, 'all hashed peers - bad consistent');

like(http_get('/busy'), qr/X-IP: 127.0.0.1:$p1, bad/,
	'upstream name - busy');
like(http_get('/cbusy'), qr/X-IP: 127.0.0.1:$p1, cbad/,
	'upstream name - busy consistent');

###############################################################################

# Returns true if two arrays follow consistency, i.e., they may only differ
# by @args present in $p, but absent in $p2, for the same indices.

sub cmp_peers {
	my ($p, $p2, @args) = @_;

	for my $i (0 .. $#$p) {
		next if @{$p}[$i] == @{$p2}[$i];
		next if (grep $_ == @{$p}[$i], @args);
		return 0;
	}

	return 1;
}

# series of requests, each with unique hash key

sub iter {
	my ($uri, $count) = @_;
	my @res;

	for my $i (1 .. $count) {
		if (http_get("$uri/?a=$i") =~ /X-Port: (\d+)/) {
			push @res, $1 if defined $1;
		}
	}

	return @res;
}

sub many {
	my ($uri, $count) = @_;
	my %ports;

	for (1 .. $count) {
		if (http_get($uri) =~ /X-Port: (\d+)/) {
			$ports{$1} = 0 unless defined $ports{$1};
			$ports{$1}++;
		}
	}

	my @keys = map { my $p = $_; grep { $p == $_ } keys %ports } @ports;
	return join ', ', map { $_ . ": " . $ports{$_} } @keys;
}

###############################################################################
