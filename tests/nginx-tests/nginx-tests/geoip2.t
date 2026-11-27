#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for the geoip module using MaxMind DB (mmdb) databases.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ AF_INET AF_INET6 inet_pton /;

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

    geoip_country  %%TESTDIR%%/country.mmdb;
    geoip_city     %%TESTDIR%%/city.mmdb;
    geoip_org      %%TESTDIR%%/org.mmdb;

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

$t->write_file('country.mmdb', write_mmdb('GeoLite2-Country-Test', [
	[ '81.2.69.160', { country => { iso_code => 'GB',
		names => { en => 'United Kingdom' } } } ],
	[ '2001:218::', { country => { iso_code => 'JP',
		names => { en => 'Japan' } } } ],
	[ '203.0.113.1', { country => { iso_code => 'ZZ' } } ],
	[ '203.0.113.2', { country => { iso_code => mmdb_uint32(42) } } ],
]));

$t->write_file('city.mmdb', write_mmdb('GeoLite2-City-Test', [
	[ '81.2.69.160', {
		continent => { code => 'EU' },
		country => { iso_code => 'GB',
			names => { en => 'United Kingdom' } },
		city => { names => { en => 'London' } },
		subdivisions => [ { iso_code => 'ENG',
			names => { en => 'England' } } ],
		postal => { code => 'EC1A' },
		location => { latitude => mmdb_double(51.5142),
			longitude => mmdb_double(-0.0931),
			metro_code => mmdb_uint32(826) },
	} ],
	[ '198.51.100.1', { location => { latitude => mmdb_float(12.5),
		longitude => mmdb_float(-45.25),
		metro_code => mmdb_uint16(500) } } ],
	[ '198.51.100.2', { location => { metro_code => mmdb_int32(-5) } } ],
	[ '198.51.100.3', { location => { latitude => mmdb_uint32(100),
		longitude => mmdb_uint32(100),
		metro_code => mmdb_uint64(999) } } ],
]));

$t->write_file('org.mmdb', write_mmdb('GeoLite2-ASN-Test', [
	[ '81.2.69.160', { autonomous_system_organization => 'Nginx' } ],
	[ '1.128.0.0',
		{ autonomous_system_organization => 'Telstra Pty Ltd' } ],
	[ '1.128.0.1', { isp => 'Example ISP' } ],
	[ '1.128.0.2', { organization => 'Example Organization' } ],
	[ '1.128.0.3', { domain => 'example.com' } ],
	[ '1.128.0.4', { network => 'no recognized org field' } ],
	[ '1.128.0.5', {
		autonomous_system_organization => 'Telstra Pty Ltd',
		isp => 'Example ISP',
		organization => 'Example Organization',
		domain => 'example.com' } ],
	[ '1.128.0.6', { isp => 'Example ISP', domain => 'example.com' } ],
	[ '1.128.0.7', { autonomous_system_organization => mmdb_uint32(42),
		isp => 'Example ISP' } ],
], 4));

$t->write_file('index.html', '');
$t->try_run('mmdb not supported')->plan(42);

###############################################################################

my $r = http_xff('81.2.69.160');
like($r, qr/X-Country-Code: GB/, 'geoip country code');
like($r, qr/X-Country-Code3: GBR/, 'geoip country code 3');
like($r, qr/X-Country-Name: United Kingdom/, 'geoip country name');

unlike($r, qr/X-Area-Code:/, 'geoip area code');
like($r, qr/X-C-Continent-Code: EU/, 'geoip city continent code');
like($r, qr/X-C-Country-Code: GB/, 'geoip city country code');
like($r, qr/X-C-Country-Code3: GBR/, 'geoip city country code 3');
like($r, qr/X-C-Country-Name: United Kingdom/, 'geoip city country name');
like($r, qr/X-Dma-Code: 826/, 'geoip dma code');
like($r, qr/X-Latitude: 51.5142/, 'geoip latitude');
like($r, qr/X-Longitude: -0.0931/, 'geoip longitude');
like($r, qr/X-Region: ENG/, 'geoip region');
like($r, qr/X-Region-Name: England/, 'geoip region name');
like($r, qr/X-City: London/, 'geoip city');
like($r, qr/X-Postal-Code: EC1A/, 'geoip postal code');

like($r, qr/X-Org: Nginx/, 'geoip org');

like(http_xff('::ffff:81.2.69.160'), qr/X-Org: Nginx/,
	'geoip ipv6 ipv4-mapped');

$r = http_xff('2001:218::');
like($r, qr/X-Country-Code: JP/, 'geoip ipv6 country code');
like($r, qr/X-Country-Code3: JPN/, 'geoip ipv6 country code 3');
like($r, qr/X-Country-Name: Japan/, 'geoip ipv6 country name');

like(http_xff('1.128.0.0'), qr/X-Org: Telstra Pty Ltd/,
	'geoip mmdb org asorg');
like(http_xff('::ffff:1.128.0.0'), qr/X-Org: Telstra Pty Ltd/,
	'geoip mmdb ipv4-mapped org ipv4-only db');

$r = http_xff('10.0.0.1');
unlike($r, qr/X-Country-Code:/, 'geoip mmdb private ip - no country code');
unlike($r, qr/X-City:/, 'geoip mmdb private ip - no city');

$r = http_xff('203.0.113.1');
like($r, qr/X-Country-Code: ZZ/, 'geoip mmdb unmapped country code');
unlike($r, qr/X-Country-Code3:/, 'geoip mmdb unmapped country code 3');

unlike(http_xff('203.0.113.2'), qr/X-Country-Code:/,
	'geoip mmdb wrong value type');

$r = http_xff('198.51.100.1');
like($r, qr/X-Latitude: 12.5000/, 'geoip mmdb float latitude');
like($r, qr/X-Longitude: -45.2500/, 'geoip mmdb float longitude');
like($r, qr/X-Dma-Code: 500/, 'geoip mmdb dma code uint16');

like(http_xff('198.51.100.2'), qr/X-Dma-Code: -5/,
	'geoip mmdb dma code int32');

like(http_xff('1.128.0.1'), qr/X-Org: Example ISP/, 'geoip mmdb org isp');
like(http_xff('1.128.0.2'), qr/X-Org: Example Organization/,
	'geoip mmdb org organization');
like(http_xff('1.128.0.3'), qr/X-Org: example.com/, 'geoip mmdb org domain');

$r = http_xff('198.51.100.3');
unlike($r, qr/X-Latitude:/, 'geoip mmdb float unsupported type');
unlike($r, qr/X-Longitude:/, 'geoip mmdb float unsupported type longitude');
unlike($r, qr/X-Dma-Code:/, 'geoip mmdb int unsupported type');

unlike(http_xff('1.128.0.4'), qr/X-Org:/,
	'geoip mmdb org no recognized field');
unlike(http_xff('2001:db8::1'), qr/X-Org:/,
	'geoip mmdb org ipv4-only db declines genuine ipv6');

like(http_xff('1.128.0.5'), qr/X-Org: Telstra Pty Ltd/,
	'geoip mmdb org precedence all fields');
like(http_xff('1.128.0.6'), qr/X-Org: Example ISP/,
	'geoip mmdb org precedence isp over domain');
like(http_xff('1.128.0.7'), qr/X-Org: Example ISP/,
	'geoip mmdb org non-string field falls through');

###############################################################################

sub http_xff {
	my ($xff) = @_;
	return http(<<EOF);
GET / HTTP/1.0
Host: localhost
X-Forwarded-For: $xff

EOF
}

###############################################################################

sub mmdb_double { bless { v => $_[0] }, 'mmdb_double' }
sub mmdb_float  { bless { v => $_[0] }, 'mmdb_float' }
sub mmdb_uint32 { bless { v => $_[0] }, 'mmdb_uint32' }
sub mmdb_int32  { bless { v => $_[0] }, 'mmdb_int32' }
sub mmdb_uint16 { bless { v => $_[0] }, 'mmdb_uint16' }
sub mmdb_uint64 { bless { v => $_[0] }, 'mmdb_uint64' }

sub mmdb_control_byte {
	my ($type, $size) = @_;
	my $t = $type <= 7 ? $type : 0;
	my $buf;

	if ($size < 29) {
		$buf = chr(($t << 5) | $size);

	} elsif ($size < 285) {
		$buf = chr(($t << 5) | 29) . chr($size - 29);

	} elsif ($size < 65821) {
		$buf = chr(($t << 5) | 30)
			. substr(pack('n', $size - 285), 0, 2);

	} else {
		$buf = chr(($t << 5) | 31)
			. substr(pack('N', $size - 65821), 1, 3);
	}

	$buf .= chr($type - 7) if $type > 7;

	return $buf;
}

sub mmdb_pack_uint {
	my ($template, $value) = @_;
	my $bytes = pack($template, $value);
	$bytes =~ s/^\x00+(?=.)//;
	return $bytes;
}

sub mmdb_pack_int32 {
	my ($value) = @_;
	return mmdb_pack_uint('N', $value) if $value >= 0;
	return pack('N', unpack('N', pack('l>', $value)));
}

sub mmdb_encode_value {
	my ($v) = @_;
	my $ref = ref $v;

	return mmdb_encode_map($v) if $ref eq 'HASH';
	return mmdb_encode_array($v) if $ref eq 'ARRAY';

	if ($ref eq 'mmdb_double') {
		return mmdb_control_byte(3, 8) . pack('d>', $v->{v});
	}

	if ($ref eq 'mmdb_float') {
		return mmdb_control_byte(15, 4) . pack('f>', $v->{v});
	}

	if ($ref eq 'mmdb_uint16') {
		my $b = mmdb_pack_uint('n', $v->{v});
		return mmdb_control_byte(5, length $b) . $b;
	}

	if ($ref eq 'mmdb_uint32') {
		my $b = mmdb_pack_uint('N', $v->{v});
		return mmdb_control_byte(6, length $b) . $b;
	}

	if ($ref eq 'mmdb_int32') {
		my $b = mmdb_pack_int32($v->{v});
		return mmdb_control_byte(8, length $b) . $b;
	}

	if ($ref eq 'mmdb_uint64') {
		my $b = mmdb_pack_uint('Q>', $v->{v});
		return mmdb_control_byte(9, length $b) . $b;
	}

	die "unsupported mmdb value: $ref" if $ref;

	return mmdb_control_byte(2, length $v) . $v;
}

sub mmdb_encode_map {
	my ($h) = @_;
	my $out = mmdb_control_byte(7, scalar keys %$h);

	for my $k (sort keys %$h) {
		$out .= mmdb_control_byte(2, length $k) . $k;
		$out .= mmdb_encode_value($h->{$k});
	}

	return $out;
}

sub mmdb_encode_array {
	my ($a) = @_;
	my $out = mmdb_control_byte(11, scalar @$a);
	$out .= mmdb_encode_value($_) for @$a;
	return $out;
}

sub mmdb_ip_bits {
	my ($ip, $ip_version) = @_;

	if (($ip_version // 6) == 4) {
		return join '', map { sprintf('%08b', $_) }
			unpack('C4', inet_pton(AF_INET, $ip));
	}

	my $packed = $ip =~ /:/
		? inet_pton(AF_INET6, $ip)
		: "\x00" x 12 . inet_pton(AF_INET, $ip);

	return join '', map { sprintf('%08b', $_) } unpack('C16', $packed);
}

sub write_mmdb {
	my ($database_type, $records, $ip_version) = @_;
	$ip_version //= 6;
	my $depth = $ip_version == 4 ? 32 : 128;

	my @tree = ([undef, undef]);
	my $data = '';

	for my $r (@$records) {
		my ($ips, $value) = @$r;
		my $offset = length $data;
		$data .= mmdb_encode_value($value);

		for my $ip (ref $ips eq 'ARRAY' ? @$ips : $ips) {
			my $bits = mmdb_ip_bits($ip, $ip_version);
			my $node = 0;

			for my $i (0 .. $depth - 1) {
				my $bit = substr($bits, $i, 1) eq '1' ? 1 : 0;

				if ($i == $depth - 1) {
					$tree[$node][$bit] =
						{ offset => $offset };
					next;
				}

				if (!defined $tree[$node][$bit]) {
					push @tree, [undef, undef];
					$tree[$node][$bit] = $#tree;
				}

				$node = $tree[$node][$bit];
			}
		}
	}

	my $node_count = scalar @tree;
	my $tree_buf = '';

	for my $node (@tree) {
		for my $side (0, 1) {
			my $rec = $node->[$side];
			my $value = !defined $rec ? $node_count
				: ref $rec ? $node_count + 16 + $rec->{offset}
				: $rec;

			$tree_buf .= substr(pack('N', $value), 1, 3);
		}
	}

	my $metadata = mmdb_encode_map({
		node_count => mmdb_uint32($node_count),
		record_size => mmdb_uint16(24),
		ip_version => mmdb_uint16($ip_version),
		database_type => $database_type,
		languages => ['en'],
		binary_format_major_version => mmdb_uint16(2),
		binary_format_minor_version => mmdb_uint16(0),
		build_epoch => mmdb_uint64(time()),
		description => { en => "$database_type test database" },
	});

	return $tree_buf . ("\x00" x 16) . $data
		. "\xab\xcd\xef" . 'MaxMind.com' . $metadata;
}

###############################################################################
