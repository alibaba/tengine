#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for an upstream implicitly defined by proxy_pass.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ SOCK_STREAM IPPROTO_TCP AF_INET6 /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

eval { die if $Socket::VERSION < 1.96; };
plan(skip_all => 'Socket too old for getaddrinfo') if $@;

my $t = Test::Nginx->new()->has(qw/http proxy/);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        listen       [::1]:%%PORT_8080%%;
        server_name  localhost;

        location / {
            proxy_pass http://localhost:%%PORT_8080%%/stub;
            proxy_next_upstream http_404;
            add_header X-Addr $upstream_addr always;
        }

        location /var {
            proxy_pass http://$arg_b/stub;
            proxy_next_upstream http_404;
            add_header X-Addr $upstream_addr always;
        }

        location /stub { }
    }
}

EOF

$t->try_run('no inet6 support');

my @addrs = resolve('localhost');

plan(skip_all => 'unexpected localhost') if @addrs > 2
	|| grep { $_ ne '127.0.0.1' && $_ ne '[::1]' } @addrs;

my $p = port(8080);
my $exp = qr/$addrs[0]:$p/ if @addrs == 1;
my $v1 = "$addrs[0]:$p", my $v2 = "$addrs[1]:$p" if @addrs == 2;
$exp = qr/\Q$v1, $v2\E|\Q$v2, $v1\E/ if @addrs == 2;

$t->plan(3);

###############################################################################

like(http_get('/'), qr/Not Found/, 'implicit upstream');
like(http_get('/'), $exp, 'implicit upstream all tried');
like(http_get("/var?b=localhost:$p"), qr/Not Found/,
	'implicit upstream by variable');

###############################################################################

sub resolve {
	my ($name) = @_;

	my $ai_addrconfig = eval { Socket::AI_ADDRCONFIG() };
	my ($err, @res) = Socket::getaddrinfo($name, "",
		{ socktype => SOCK_STREAM, protocol => IPPROTO_TCP,
			flags => $ai_addrconfig });
	die "Cannot getaddrinfo - $err" if $err;

	my @addrs;
	foreach my $ai (@res) {
		my ($err, $addr) = Socket::getnameinfo($ai->{addr},
			Socket::NI_NUMERICHOST(), Socket::NIx_NOSERV());
		die "Cannot getnameinfo - $err" if $err;
		$addr = '[' . $addr . ']' if $ai->{family} == AF_INET6;
		push @addrs, $addr;
	}
	return @addrs;
}

###############################################################################
