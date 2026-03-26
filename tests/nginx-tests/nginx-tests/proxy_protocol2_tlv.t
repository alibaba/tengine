#!/usr/bin/perl

# (C) Roman Arutyunyan
# (C) Eugene Grebenschikov
# (C) Nginx, Inc.

# Tests for variables for proxy protocol v2 TLVs.

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

my $t = Test::Nginx->new()->has(qw/http map/)->plan(14)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    map $proxy_protocol_tlv_ssl $binary_present {
        "~\\x00" "true";
    }

    add_header X-ALPN
        $proxy_protocol_tlv_alpn-$proxy_protocol_tlv_0x01;
    add_header X-AUTHORITY
        $proxy_protocol_tlv_authority-$proxy_protocol_tlv_0x02;
    add_header X-UNIQUE-ID
        $proxy_protocol_tlv_unique_id-$proxy_protocol_tlv_0x05;
    add_header X-NETNS
        $proxy_protocol_tlv_netns-$proxy_protocol_tlv_0x30;
    add_header X-SSL-VERIFY
        $proxy_protocol_tlv_ssl_verify;
    add_header X-SSL-VERSION
        $proxy_protocol_tlv_ssl_version-$proxy_protocol_tlv_ssl_0x21;
    add_header X-SSL-CN
        $proxy_protocol_tlv_ssl_cn-$proxy_protocol_tlv_ssl_0x22;
    add_header X-SSL-CIPHER
        $proxy_protocol_tlv_ssl_cipher-$proxy_protocol_tlv_ssl_0x23;
    add_header X-SSL-SIG-ALG
        $proxy_protocol_tlv_ssl_sig_alg-$proxy_protocol_tlv_ssl_0x24;
    add_header X-SSL-KEY-ALG
        $proxy_protocol_tlv_ssl_key_alg-$proxy_protocol_tlv_ssl_0x25;
    add_header X-TLV-CRC32C
        $proxy_protocol_tlv_0x3;
    add_header X-TLV-CUSTOM
        $proxy_protocol_tlv_0x000ae;
    add_header X-TLV-X
        $proxy_protocol_tlv_0x000e-$proxy_protocol_tlv_0x0f;
    add_header X-SSL-BINARY
        $binary_present;

    server {
        listen       127.0.0.1:8080 proxy_protocol;
        server_name  localhost;

        location / { }
    }
}

EOF

$t->write_file('t1', 'SEE-THIS');
$t->run();

###############################################################################

my $tlv = pp2_create_tlv(0x1, "ALPN1");
$tlv .= pp2_create_tlv(0x2, "localhost");
$tlv .= pp2_create_tlv(0x3, "4321");
$tlv .= pp2_create_tlv(0x5, "UNIQQ");

my $sub = pp2_create_tlv(0x21, "TLSv1.2");
$sub .= pp2_create_tlv(0x22, "example.com");
$sub .= pp2_create_tlv(0x23, "AES256-SHA");
$sub .= pp2_create_tlv(0x24, "SHA1");
$sub .= pp2_create_tlv(0x25, "RSA512");
my $ssl = pp2_create_ssl(0x01, 255, $sub);
$tlv .= pp2_create_tlv(0x20, $ssl);

$tlv .= pp2_create_tlv(0x30, "NETNS");
$tlv .= pp2_create_tlv(0xae, "12345");
my $p = pp2_create($tlv);

my $r = pp_get('/t1', $p);
like($r, qr/X-ALPN: ALPN1-ALPN1\x0d?$/m, 'ALPN');
like($r, qr/X-AUTHORITY: localhost-localhost\x0d?$/m, 'AUTHORITY');
like($r, qr/X-TLV-CRC32C: 4321\x0d?$/m, 'CRC32C');
like($r, qr/X-UNIQUE-ID: UNIQQ-UNIQQ\x0d?$/m, 'UNIQUE_ID');
like($r, qr/X-SSL-VERIFY: 255\x0d?$/m, 'SSL_VERIFY');
like($r, qr/X-SSL-VERSION: TLSv1.2-TLSv1.2\x0d?$/m, 'SSL_VERSION');
like($r, qr/X-SSL-CN: example.com-example.com\x0d?$/m, 'SSL_CN');
like($r, qr/X-SSL-CIPHER: AES256-SHA-AES256-SHA\x0d?$/m, 'SSL_CIPHER');
like($r, qr/X-SSL-SIG-ALG: SHA1-SHA1\x0d?$/m, 'SSL_SIG_ALG');
like($r, qr/X-SSL-KEY-ALG: RSA512-RSA512\x0d?$/m, 'SSL_KEY_ALG');
like($r, qr/X-NETNS: NETNS-NETNS\x0d?$/m, 'NETNS');
like($r, qr/X-TLV-CUSTOM: 12345\x0d?$/m, 'custom');
like($r, qr/X-TLV-X: -\x0d?$/m, 'non-existent');

SKIP: {
skip 'no PCRE', 1 unless $t->has_module('rewrite');

like($r, qr/X-SSL-BINARY: true/, 'SSL_BINARY');

}

###############################################################################

sub pp_get {
	my ($url, $proxy) = @_;
	return http($proxy . <<EOF);
GET $url HTTP/1.0
Host: localhost

EOF
}

sub pp2_create {
	my ($tlv) = @_;

	my $pp2_sig = pack("N3", 0x0D0A0D0A, 0x000D0A51, 0x5549540A);
	my $ver_cmd = pack('C', 0x21);
	my $family = pack('C', 0x11);
	my $packet = $pp2_sig . $ver_cmd . $family;

	my $ip1 = pack('N', 0xc0000201); # 192.0.2.1
	my $ip2 = pack('N', 0xc0000202); # 192.0.2.2
	my $port1 = pack('n', 123);
	my $port2 = pack('n', 5678);
	my $addrs = $ip1 . $ip2 . $port1 . $port2;

	my $len = length($addrs) + length($tlv);

	$packet .= pack('n', $len) . $addrs . $tlv;

	return $packet;
}

sub pp2_create_tlv {
	my ($type, $content) = @_;

	my $len = length($content);

	return pack("CnA*", $type, $len, $content);
}

sub pp2_create_ssl {
	my ($client, $verify, $content) = @_;

	return pack("CNA*", $client, $verify, $content);
}

###############################################################################
