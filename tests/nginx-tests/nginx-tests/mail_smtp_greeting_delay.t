#!/usr/bin/perl

# (C) Maxim Dounin

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

my $t = Test::Nginx->new()->has(qw/mail smtp/)->plan(2)
	->write_file_expand('nginx.conf', <<'EOF')->run();

%%TEST_GLOBALS%%

daemon off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;
    xclient    off;

    server {
        listen     127.0.0.1:8025;
        protocol   smtp;
        smtp_greeting_delay  1s;
    }
}

EOF

###############################################################################

# With smtp_greeting_delay session expected to be closed after first error
# message if client sent something before greeting.

my $s = Test::Nginx::SMTP->new();
$s->send('HELO example.com');
$s->check(qr/^5.. /, "command before greeting - session must be rejected");
ok($s->eof(), "session have to be closed");

###############################################################################
