#!/usr/bin/perl

# (C) Andrey Zelenkov
# (C) Nginx, Inc.

# Tests for geoip module.

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

my $t = Test::Nginx->new()->has(qw/http http_geoip/)
	->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    geoip_proxy    127.0.0.1/32;

    geoip_country  %%TESTDIR%%/country.dat;
    geoip_city     %%TESTDIR%%/city.dat;
    geoip_org      %%TESTDIR%%/org.dat;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            add_header X-Country-Code      $geoip_country_code;
            add_header X-Country-Code3     $geoip_country_code3;
            add_header X-Country-Name      $geoip_country_name;

            add_header X-Area-Code         $geoip_area_code;
            add_header X-C-Continent-Code  $geoip_city_continent_code;
            add_header X-C-Country-Code    $geoip_city_country_code;
            add_header X-C-Country-Code3   $geoip_city_country_code3;
            add_header X-C-Country-Name    $geoip_city_country_name;
            add_header X-Dma-Code          $geoip_dma_code;
            add_header X-Latitude          $geoip_latitude;
            add_header X-Longitude         $geoip_longitude;
            add_header X-Region            $geoip_region;
            add_header X-Region-Name       $geoip_region_name;
            add_header X-City              $geoip_city;
            add_header X-Postal-Code       $geoip_postal_code;

            add_header X-Org               $geoip_org;
        }
    }
}

EOF

my $d = $t->testdir();

# country database:
#
# "10.0.0.1","10.0.0.1","RU","Russian Federation"
# "2001:db8::","2001:db8::","US","United States"

my $data = '';

for my $i (0 .. 156) {
	# skip to offset 32 if 1st bit set in ipv6 address wins
	$data .= pack_node($i + 1) . pack_node(32), next if $i == 2;
	# otherwise default to RU
	$data .= pack_node(0xffffb9) . pack_node(0xffff00), next if $i == 31;
	# continue checking bits set in ipv6 address
	$data .= pack_node(0xffff00) . pack_node($i + 1), next
		if grep $_ == $i, (44, 49, 50, 52, 53, 55, 56, 57);
	# last bit set in ipv6 address
	$data .= pack_node(0xffffe1) . pack_node(0xffff00), next if $i == 156;
	$data .= pack_node($i + 1) . pack_node(0xffff00);
}

$data .= chr(0x00) x 3;
$data .= chr(0xFF) x 3;
$data .= chr(12);

$t->write_file('country.dat', $data);

# city database:
#
# "167772161","167772161","RU","48","Moscow","119034","55.7543",37.6202",,

$data = '';

for my $i (0 .. 31) {
	$data .= pack_node(32) . pack_node($i + 1), next if $i == 4 or $i == 6;
	$data .= pack_node(32) . pack_node($i + 2), next if $i == 31;
	$data .= pack_node($i + 1) . pack_node(32);
}

$data .= chr(42);
$data .= chr(185);
$data .= pack('Z*', 48);
$data .= pack('Z*', 'Moscow');
$data .= pack('Z*', 119034);
$data .= pack_node(int((55.7543 + 180) * 10000));
$data .= pack_node(int((37.6202 + 180) * 10000));
$data .= chr(0) x 3;
$data .= chr(0xFF) x 3;
$data .= chr(2);
$data .= pack_node(32);

$t->write_file('city.dat', $data);

# organization database:
#
# "167772161","167772161","Nginx"

$data = '';

for my $i (0 .. 31) {
	$data .= pack_org(32) . pack_org($i + 1), next if $i == 4 or $i == 6;
	$data .= pack_org(32) . pack_org($i + 2), next if $i == 31;
	$data .= pack_org($i + 1) . pack_org(32);
}

$data .= chr(42);
$data .= pack('Z*', 'Nginx');
$data .= chr(0xFF) x 3;
$data .= chr(5);
$data .= pack_node(32);

$t->write_file('org.dat', $data);
$t->write_file('index.html', '');
$t->try_run('no inet6 support')->plan(20);

###############################################################################

my $r = http_xff('10.0.0.1');
like($r, qr/X-Country-Code: RU/, 'geoip country code');
like($r, qr/X-Country-Code3: RUS/, 'geoip country code 3');
like($r, qr/X-Country-Name: Russian Federation/, 'geoip country name');

like($r, qr/X-Area-Code: 0/, 'geoip area code');
like($r, qr/X-C-Continent-Code: EU/, 'geoip city continent code');
like($r, qr/X-C-Country-Code: RU/, 'geoip city country code');
like($r, qr/X-C-Country-Code3: RUS/, 'geoip city country code 3');
like($r, qr/X-C-Country-Name: Russian Federation/, 'geoip city country name');
like($r, qr/X-Dma-Code: 0/, 'geoip dma code');
like($r, qr/X-Latitude: 55.7543/, 'geoip latitude');
like($r, qr/X-Longitude: 37.6202/, 'geoip longitude');
like($r, qr/X-Region: 48/, 'geoip region');
like($r, qr/X-Region-Name: Moscow City/, 'geoip region name');
like($r, qr/X-City: Moscow/, 'geoip city');
like($r, qr/X-Postal-Code: 119034/, 'geoip postal code');

like($r, qr/X-Org: Nginx/, 'geoip org');

like(http_xff('::ffff:10.0.0.1'), qr/X-Org: Nginx/, 'geoip ipv6 ipv4-mapped');

$r = http_xff('2001:db8::');
like($r, qr/X-Country-Code: US/, 'geoip ipv6 country code');
like($r, qr/X-Country-Code3: USA/, 'geoip ipv6 country code 3');
like($r, qr/X-Country-Name: United States/, 'geoip ipv6 country name');

###############################################################################

sub http_xff {
	my ($xff) = @_;
	return http(<<EOF);
GET / HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

sub pack_node {
	substr pack('V', shift), 0, 3;
}

sub pack_org {
	pack('V', shift);
}

###############################################################################
