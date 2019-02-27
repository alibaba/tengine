#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for mail resolver.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::SMTP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

local $SIG{PIPE} = 'IGNORE';

my $t = Test::Nginx->new()->has(qw/mail smtp http rewrite/)->plan(8)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    auth_http    http://127.0.0.1:8080/mail/auth;
    smtp_auth    none;
    server_name  locahost;

    # prevent useless resend
    resolver_timeout 2s;

    server {
        listen    127.0.0.1:8025;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8981_UDP%%
                  127.0.0.1:%%PORT_8982_UDP%%
                  127.0.0.1:%%PORT_8983_UDP%%;
    }

    server {
        listen    127.0.0.1:8027;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8982_UDP%%;
    }

    server {
        listen    127.0.0.1:8028;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8983_UDP%%;
        resolver_timeout 1s;
    }

    server {
        listen    127.0.0.1:8029;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8984_UDP%%;
    }

    server {
        listen    127.0.0.1:8030;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8985_UDP%%;
    }

    server {
        listen    127.0.0.1:8031;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8986_UDP%%;
        resolver_timeout 1s;
    }

    server {
        listen    127.0.0.1:8032;
        protocol  smtp;
        resolver  127.0.0.1:%%PORT_8987_UDP%%;
    }

}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            set $reply $http_client_host;

            if ($http_client_host !~ UNAVAIL) {
                set $reply OK;
            }

            add_header Auth-Status $reply;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port %%PORT_8026%%;
            return 204;
        }
    }
}

EOF

$t->run_daemon(\&Test::Nginx::SMTP::smtp_test_daemon);
$t->run_daemon(\&dns_daemon, port($_), $t) foreach (8981 .. 8987);

$t->run();

$t->waitforsocket('127.0.0.1:' . port(8026));
$t->waitforfile($t->testdir . '/' . port($_)) foreach (8981 .. 8987);

###############################################################################

# PTR

my $s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->ok('PTR');

$s->send('QUIT');
$s->read();

# Cached PTR prevents from querying bad ns on port 8983

$s = Test::Nginx::SMTP->new();
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->ok('PTR cached');

$s->send('QUIT');
$s->read();

# SERVFAIL

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8027));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->check(qr/TEMPUNAVAIL/, 'PTR SERVFAIL');

$s->send('QUIT');
$s->read();

# PTR with zero length RDATA

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8028));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->check(qr/TEMPUNAVAIL/, 'PTR empty');

$s->send('QUIT');
$s->read();

# CNAME

TODO: {
local $TODO = 'support for CNAME RR';

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8029));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->ok('CNAME');

$s->send('QUIT');
$s->read();

}

# uncompressed answer

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8030));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->ok('uncompressed PTR');

$s->send('QUIT');
$s->read();

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8031));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->check(qr/TEMPUNAVAIL/, 'PTR type');

$s->send('QUIT');
$s->read();

# CNAME and PTR in one answer section

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8032));
$s->read();
$s->send('EHLO example.com');
$s->read();
$s->send('MAIL FROM:<test@example.com> SIZE=100');
$s->read();

$s->send('RCPT TO:<test@example.com>');
$s->ok('CNAME with PTR');

$s->send('QUIT');
$s->read();

###############################################################################

sub reply_handler {
	my ($recv_data, $port) = @_;

	my (@name, @rdata);

	use constant NOERROR	=> 0;
	use constant SERVFAIL	=> 2;
	use constant NXDOMAIN	=> 3;

	use constant A		=> 1;
	use constant CNAME	=> 5;
	use constant PTR	=> 12;
	use constant DNAME	=> 39;

	use constant IN		=> 1;

	# default values

	my ($hdr, $rcode, $ttl) = (0x8180, NOERROR, 3600);

	# decode name

	my ($len, $offset) = (undef, 12);
	while (1) {
		$len = unpack("\@$offset C", $recv_data);
		last if $len == 0;
		$offset++;
		push @name, unpack("\@$offset A$len", $recv_data);
		$offset += $len;
	}

	$offset -= 1;
	my ($id, $type, $class) = unpack("n x$offset n2", $recv_data);

	my $name = join('.', @name);
	if ($name eq 'a.example.net' && $type == A) {
		push @rdata, rd_addr($ttl, '127.0.0.1');

	} elsif ($name eq '1.0.0.127.in-addr.arpa' && $type == PTR) {
		if ($port == port(8981)) {
			push @rdata, rd_name(PTR, $ttl, 'a.example.net');

		} elsif ($port == port(8982)) {
			$rcode = SERVFAIL;

		} elsif ($port == port(8983)) {
			# zero length RDATA

			push @rdata, pack("n3N n", 0xc00c, PTR, IN, $ttl, 0);

		} elsif ($port == port(8984)) {
			# PTR answered with CNAME

			push @rdata, rd_name(CNAME, $ttl,
				'1.1.0.0.127.in-addr.arpa');

		} elsif ($port == port(8985)) {
			# uncompressed answer

			push @rdata, pack("(C/a*)6x n2N n(C/a*)3x",
				('1', '0', '0', '127', 'in-addr', 'arpa'),
				PTR, IN, $ttl, 15, ('a', 'example', 'net'));

		} elsif ($port == port(8986)) {
			push @rdata, rd_name(DNAME, $ttl, 'a.example.net');

		} elsif ($port == port(8987)) {
			# PTR answered with CNAME+PTR

			push @rdata, rd_name(CNAME, $ttl,
				'1.1.0.0.127.in-addr.arpa');
			push @rdata, pack("n3N n(C/a*)3 x", 0xc034,
				PTR, IN, $ttl, 15, ('a', 'example', 'net'));
		}

	} elsif ($name eq '1.1.0.0.127.in-addr.arpa' && $type == PTR) {
		push @rdata, rd_name(PTR, $ttl, 'a.example.net');
	}

	$len = @name;
	pack("n6 (C/a*)$len x n2", $id, $hdr | $rcode, 1, scalar @rdata,
		0, 0, @name, $type, $class) . join('', @rdata);
}

sub rd_name {
	my ($type, $ttl, $name) = @_;
	my ($rdlen, @rdname);

	@rdname = split /\./, $name;
	$rdlen = length(join '', @rdname) + @rdname + 1;
	pack("n3N n(C/a*)* x", 0xc00c, $type, IN, $ttl, $rdlen, @rdname);
}

sub rd_addr {
	my ($ttl, $addr) = @_;

	my $code = 'split(/\./, $addr)';

	# use a special pack string to not zero pad

	return pack 'n3N', 0xc00c, A, IN, $ttl if $addr eq '';

	pack 'n3N nC4', 0xc00c, A, IN, $ttl, eval "scalar $code", eval($code);
}

sub dns_daemon {
	my ($port, $t) = @_;

	my ($data, $recv_data);
	my $socket = IO::Socket::INET->new(
		LocalAddr => '127.0.0.1',
		LocalPort => $port,
		Proto => 'udp',
	)
		or die "Can't create listening socket: $!\n";

	# signal we are ready

	open my $fh, '>', $t->testdir() . '/' . $port;
	close $fh;

	while (1) {
		$socket->recv($recv_data, 65536);
		$data = reply_handler($recv_data, $port);
		$socket->send($data);
	}
}

###############################################################################
