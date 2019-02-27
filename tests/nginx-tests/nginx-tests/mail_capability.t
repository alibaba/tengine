#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for imap/pop3/smtp capabilities.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;
use Test::Nginx::POP3;
use Test::Nginx::SMTP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/mail mail_ssl imap pop3 smtp/)
	->has_daemon('openssl')->plan(17);

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    ssl_certificate_key localhost.key;
    ssl_certificate localhost.crt;

    auth_http  http://127.0.0.1:8080; # unused

    pop3_auth  plain apop cram-md5;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;
        imap_capabilities SEE-THIS;
    }

    server {
        listen     127.0.0.1:8144;
        protocol   imap;
        starttls   on;
    }

    server {
        listen     127.0.0.1:8145;
        protocol   imap;
        starttls   only;
    }

    server {
        listen     127.0.0.1:8110;
        protocol   pop3;
    }

    server {
        listen     127.0.0.1:8111;
        protocol   pop3;
        starttls   on;
    }

    server {
        listen     127.0.0.1:8112;
        protocol   pop3;
        starttls   only;
    }

    server {
        listen     127.0.0.1:8025;
        protocol   smtp;
        starttls   off;
    }

    server {
        listen     127.0.0.1:8026;
        protocol   smtp;
        starttls   on;
    }

    server {
        listen     127.0.0.1:8027;
        protocol   smtp;
        starttls   only;
    }
}

EOF

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

$t->run();

###############################################################################

# imap, custom capabilities

my $s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 CAPABILITY');
$s->check(qr/^\* CAPABILITY SEE-THIS AUTH=PLAIN/, 'imap capability');
$s->ok('imap capability completed');

# imap starttls

$s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:' . port(8144));
$s->read();

$s->send('1 CAPABILITY');
$s->check(qr/^\* CAPABILITY IMAP4 IMAP4rev1 UIDPLUS AUTH=PLAIN STARTTLS/,
	'imap capability starttls');

# imap starttls only

$s = Test::Nginx::IMAP->new(PeerAddr => '127.0.0.1:' . port(8145));
$s->read();

$s->send('1 CAPABILITY');
$s->check(qr/^\* CAPABILITY IMAP4 IMAP4rev1 UIDPLUS STARTTLS LOGINDISABLED/,
	'imap capability starttls only');

# pop3

$s = Test::Nginx::POP3->new(PeerAddr => '127.0.0.1:' . port(8110));
$s->read();

$s->send('CAPA');
$s->ok('pop3 capa');

my $caps = get_auth_caps($s);
like($caps, qr/USER/, 'pop3 - user');
like($caps, qr/SASL (PLAIN LOGIN|LOGIN PLAIN) CRAM-MD5/, 'pop3 - methods');
unlike($caps, qr/STLS/, 'pop3 - no stls');

# pop3 starttls

$s = Test::Nginx::POP3->new(PeerAddr => '127.0.0.1:' . port(8111));
$s->read();

$s->send('CAPA');

$caps = get_auth_caps($s);
like($caps, qr/USER/, 'pop3 starttls - user');
like($caps, qr/SASL (PLAIN LOGIN|LOGIN PLAIN) CRAM-MD5/,
	'pop3 starttls - methods');
like($caps, qr/STLS/, 'pop3 startls - stls');

# pop3 starttls only

$s = Test::Nginx::POP3->new(PeerAddr => '127.0.0.1:' . port(8112));
$s->read();

$s->send('CAPA');

$caps = get_auth_caps($s);
unlike($caps, qr/USER/, 'pop3 starttls only - no user');
unlike($caps, qr/SASL/, 'pop3 starttls only - no methods');
like($caps, qr/STLS/, 'pop3 startls only - stls');

# smtp

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8025));
$s->read();

$s->send('EHLO example.com');
$s->check(qr/^250 AUTH PLAIN LOGIN\x0d\x0a?/, 'smtp ehlo');

# smtp starttls

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8026));
$s->read();

$s->send('EHLO example.com');
$s->check(qr/^250 STARTTLS/, 'smtp ehlo - starttls');

# smtp starttls only

$s = Test::Nginx::SMTP->new(PeerAddr => '127.0.0.1:' . port(8027));
$s->read();

$s->send('EHLO example.com');
$s->check(qr/^250 STARTTLS/, 'smtp ehlo - starttls only');

###############################################################################

sub get_auth_caps {
	my ($s) = @_;
	my @meth;

	while ($s->read()) {
		last if /^\./;
		push @meth, $1 if /(.*?)\x0d\x0a?/ms;
	}
	join ':', @meth;
}

###############################################################################
