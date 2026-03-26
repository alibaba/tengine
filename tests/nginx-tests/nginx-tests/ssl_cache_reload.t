#!/usr/bin/perl

# (C) Sergey Kandaurov
# (C) Nginx, Inc.

# Tests for SSL object cache inheritance on configuration reload.

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

my $t = Test::Nginx->new()->has(qw/http http_ssl socket_ssl/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', << 'EOF');

%%TEST_GLOBALS%%

daemon off;

ssl_object_cache_inheritable on;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8443 ssl;
        server_name  localhost;

        ssl_certificate 1.example.com.crt;
        ssl_certificate_key 1.example.com.key;
    }

    server {
        listen       127.0.0.1:8444 ssl;
        server_name  localhost;

        ssl_certificate 2.example.com.crt;
        ssl_certificate_key 2.example.com.key;
    }
}

EOF

my $d = $t->testdir();

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

foreach my $name ('1.example.com', '2.example.com', '3.example.com') {
	system('openssl req -x509 -new '
		. "-config $d/openssl.conf -subj /CN=$name/ "
		. "-out $d/$name.crt -keyout $d/$name.key "
		. ">>$d/openssl.out 2>&1") == 0
		or die "Can't create certificate for $name: $!\n";
}

$t->try_run('no ssl_object_cache_inheritable')->plan(5);

###############################################################################

# make sure SSL certificates are properly cached on configuration reload by:
#
# - updating backing storage
# - keeping inode and mtime metadata
#   (on win32, File ID appears to be modified by in-place rewrite)

like(get_cert_cn(8443), qr!/CN=1.example.com!, 'certificate 1');
like(get_cert_cn(8444), qr!/CN=2.example.com!, 'certificate 2');

update($t, "1.example.com", "3.example.com", update_metadata => 1);
update($t, "2.example.com", "3.example.com") unless $^O eq 'MSWin32';

ok(reload($t), 'reload');

like(get_cert_cn(8443), qr!/CN=3.example.com!, 'certificate updated');
like(get_cert_cn(8444), qr!/CN=2.example.com!, 'certificate cached');

###############################################################################

sub get_cert_cn {
	my ($port) = @_;
	my $s = http('',
		start => 1,
		PeerAddr => '127.0.0.1:' . port($port),
		SSL => 1);
	return $s->dump_peer_certificate();
}

sub update {
	my ($t, $old, $new, %extra) = @_;

	for my $ext ("crt", "key") {
		if ($extra{update_metadata}) {
			$t->write_file("$old.$ext.tmp",
				$t->read_file("$new.$ext"));
			rename("$d/$old.$ext.tmp", "$d/$old.$ext");

		} else {
			my $mtime = -e "$d/$old.$ext" && (stat(_))[9];
			$t->write_file("$old.$ext", $t->read_file("$new.$ext"));
			utime(time(), $mtime, "$d/$old.$ext");
		}
	}
}

sub reload {
	my ($t) = @_;

	$t->reload();

	for (1 .. 30) {
		return 1 if $t->read_file('error.log') =~ /exited with code/;
		select undef, undef, undef, 0.2;
	}
}

###############################################################################
