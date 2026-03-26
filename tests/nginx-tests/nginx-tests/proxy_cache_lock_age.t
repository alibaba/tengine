#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for http proxy cache lock aged.

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

my $t = Test::Nginx->new()->has(qw/http proxy cache/)->plan(4)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    proxy_cache_path   %%TESTDIR%%/cache  levels=1:2
                       keys_zone=NAME:1m;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass    http://127.0.0.1:8081;
            proxy_cache   NAME;

            proxy_cache_lock on;
            proxy_cache_lock_age 100ms;
        }
    }
}

EOF

$t->run_daemon(\&http_daemon, port(8081));
$t->run()->waitforsocket('127.0.0.1:' . port(8081));

###############################################################################

my $s = http_get('/', start => 1);

like(http_get('/'), qr/request 2/, 'request');
like(http_get('/'), qr/request 2/, 'request cached');

http_get('/close');

like(http_end($s), qr/request 1/, 'request aged');
like(http_get('/'), qr/request 1/, 'request aged cached');

###############################################################################

sub http_daemon {
	my (@ports) = @_;
	my @socks;

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
	my $num = 0;
	my $s;

	local $SIG{PIPE} = 'IGNORE';

	while (my @ready = $sel->can_read) {
		foreach my $fh (@ready) {
			if (grep $_ == $fh, @socks) {
				my $new = $fh->accept;
				$new->autoflush(1);
				$sel->add($new);

			} elsif (process_socket($fh, \$num, \$s)) {
				$sel->remove($fh);
				$fh->close;
			}
		}
	}
}

# Returns true to close connection

sub process_socket {
	my ($client, $num, $s) = @_;

	my $headers = '';
	my $uri = '';

	while (<$client>) {
		$headers .= $_;
		last if (/^\x0d?\x0a?$/);
	}
	return 1 if $headers eq '';

	$uri = $1 if $headers =~ /^\S+\s+([^ ]+)\s+HTTP/i;
	return 1 if $uri eq '';

	# finish a previously saved socket
	close $$s if $uri eq '/close';

	$$num++;

	print $client <<EOF;
HTTP/1.1 200 OK
Cache-Control: max-age=300
Connection: close

request $$num
EOF

	# save socket and wait
	if ($$num == 1) {
		$$s = $client;
		return 0;
	}

	return 1;
}

###############################################################################
