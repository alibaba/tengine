#!/usr/bin/perl

# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for http tunnel module with auth_basic.

###############################################################################

use warnings;
use strict;

use Test::More;

use MIME::Base64 qw/ encode_base64 /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http tunnel auth_basic rewrite/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        auth_basic           "closed proxy";
        auth_basic_user_file %%TESTDIR%%/htpasswd;
        tunnel_pass;
    }

    server {
        listen       127.0.0.1:8081;
        server_name  localhost;

        location / {
            return 200 "SEE-THIS";
        }
    }
}

EOF

$t->write_file('htpasswd', 'plain:' . '{PLAIN}password' . "\n");

$t->try_run('no tunnel')->plan(2);

###############################################################################

like(proxy_get('/', '127.0.0.1:' . port(8081), port(8080)), qr/ 407/,
	'CONNECT proxy auth required');
like(proxy_get('/', '127.0.0.1:' . port(8081), port(8080), user => 'plain',
	pass => 'password'), qr/SEE-THIS/, 'CONNECT proxy auth success');

###############################################################################

sub proxy_get {
	my ($uri, $host, $proxy_port, %extra) = @_;
	my $reply = '';

	my $s = IO::Socket::INET->new(
		Proto => 'tcp',
		PeerAddr => '127.0.0.1:' . $proxy_port,
	)
		or die "Can't connect to proxy 127.0.0.1:$proxy_port $!\n";

	http_connect($host, socket => $s, start => 1, %extra);

	while (<$s>) {
		$reply .= $_;
		last if /^\r?\n$/;
	}

	if ($reply =~ /200 OK/) {
		log_in($reply);
		return http_get($uri, socket => $s, %extra);

	} elsif ($reply =~ /Content-Length:\s*(\d+)/i) {
		read ($s, $_, $1);
		$reply .= $_;
	}

	$s->close;
	log_in($reply);
	return $reply;
}

sub http_connect {
	my ($host, %extra) = @_;
	my $auth_header = '';

	$auth_header = 'Proxy-Authorization: Basic '
		. encode_base64($extra{user} . ':' . $extra{pass}, '') . "\n"
		if defined $extra{user} && defined $extra{pass};

	return http(<<EOF, %extra);
CONNECT $host HTTP/1.1
Host: $host
$auth_header
EOF
}

###############################################################################
