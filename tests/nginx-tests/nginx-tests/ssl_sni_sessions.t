#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for SSL session resumption with SNI.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl sni rewrite/);

$t->has_daemon('openssl')->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    server {
        listen       127.0.0.1:8080 ssl;
        server_name  default;

        ssl_session_tickets off;
        ssl_session_cache shared:cache1:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8080;
        server_name  nocache;

        ssl_session_tickets off;
        ssl_session_cache shared:cache2:1m;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8081 ssl;
        server_name  default;

        ssl_session_ticket_key ticket1.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }

    server {
        listen       127.0.0.1:8081;
        server_name  tickets;

        ssl_session_ticket_key ticket2.key;

        location / {
            return 200 $ssl_server_name:$ssl_session_reused;
        }
    }
}

EOF

eval { require IO::Socket::SSL; die if $IO::Socket::SSL::VERSION < 1.56; };
plan(skip_all => 'IO::Socket::SSL version >= 1.56 required') if $@;

eval {
	if (IO::Socket::SSL->can('can_client_sni')) {
		IO::Socket::SSL->can_client_sni() or die;
	}
};
plan(skip_all => 'IO::Socket::SSL with OpenSSL SNI support required') if $@;

eval {
	my $ctx = Net::SSLeay::CTX_new() or die;
	my $ssl = Net::SSLeay::new($ctx) or die;
	Net::SSLeay::set_tlsext_host_name($ssl, 'example.org') == 1 or die;
};
plan(skip_all => 'Net::SSLeay with OpenSSL SNI support required') if $@;

$t->plan(6);

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

my $d = $t->testdir();

foreach my $name ('localhost') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->write_file('ticket1.key', '1' x 48);
$t->write_file('ticket2.key', '2' x 48);

$t->run();

###############################################################################

# check that everything works fine with default server

my $ctx = get_ssl_context();

like(get('default', port(8080), $ctx), qr!default:\.!, 'default server');
like(get('default', port(8080), $ctx), qr!default:r!, 'default server reused');

# check that sessions are still properly saved and restored
# when using an SNI-based virtual server with different session cache;
# as session resumption happens before SNI, only default server
# settings are expected to matter

# this didn't work before nginx 1.9.6 (and caused segfaults if no session
# cache was configured the SNI-based virtual server), because OpenSSL, when
# creating new sessions, uses callbacks from the default server context, but
# provides access to the SNI-selected server context only (ticket #235)

$ctx = get_ssl_context();

like(get('nocache', port(8080), $ctx), qr!nocache:\.!, 'without cache');
like(get('nocache', port(8080), $ctx), qr!nocache:r!, 'without cache reused');

# make sure tickets can be used if an SNI-based virtual server
# uses a different set of session ticket keys explicitly set

$ctx = get_ssl_context();

like(get('tickets', port(8081), $ctx), qr!tickets:\.!, 'tickets');
like(get('tickets', port(8081), $ctx), qr!tickets:r!, 'tickets reused');

###############################################################################

sub get_ssl_context {
	return IO::Socket::SSL::SSL_Context->new(
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_session_cache_size => 100
	);
}

sub get_ssl_socket {
	my ($host, $port, $ctx) = @_;
	my $s;

	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		local $SIG{PIPE} = sub { die "sigpipe\n" };
		alarm(8);
		$s = IO::Socket::SSL->new(
			Proto => 'tcp',
			PeerAddr => '127.0.0.1',
			PeerPort => $port,
			SSL_hostname => $host,
			SSL_reuse_ctx => $ctx,
			SSL_error_trap => sub { die $_[1] }
		);
		alarm(0);
	};
	alarm(0);

	if ($@) {
		log_in("died: $@");
		return undef;
	}

	return $s;
}

sub get {
	my ($host, $port, $ctx) = @_;

	my $s = get_ssl_socket($host, $port, $ctx) or return;
	my $r = http(<<EOF, socket => $s);
GET / HTTP/1.0
Host: $host

EOF

	$s->close();
	return $r;
}

###############################################################################
