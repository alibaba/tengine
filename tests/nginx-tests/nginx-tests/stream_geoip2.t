#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for the stream geoip module using MaxMind DB (mmdb) databases.

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ $CRLF AF_INET AF_INET6 inet_pton /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::Stream qw/ stream /;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/stream stream_geoip stream_return/)
	->has('stream_realip');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

stream {
    %%TEST_GLOBALS_STREAM%%

    set_real_ip_from  127.0.0.1/32;

    geoip_country  %%TESTDIR%%/country.mmdb;
    geoip_city     %%TESTDIR%%/city.mmdb;
    geoip_org      %%TESTDIR%%/org.mmdb;

    server {
        listen  127.0.0.1:8080 proxy_protocol;
        return  "country_code:$geoip_country_code
                 country_code3:$geoip_country_code3
                 country_name:$geoip_country_name

                 area_code:$geoip_area_code
                 city_continent_code:$geoip_city_continent_code
                 city_country_code:$geoip_city_country_code
                 city_country_code3:$geoip_city_country_code3
                 city_country_name:$geoip_city_country_name
                 dma_code:$geoip_dma_code
                 latitude:$geoip_latitude
                 longitude:$geoip_longitude
                 region:$geoip_region
                 region_name:$geoip_region_name
                 city:$geoip_city
                 postal_code:$geoip_postal_code

                 org:$geoip_org";
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

$t->try_run('mmdb not supported')->plan(42);

###############################################################################

my %data = stream_pp('81.2.69.160') =~ /(\w+):(.*)/g;
is($data{country_code}, 'GB', 'geoip country code');
is($data{country_code3}, 'GBR', 'geoip country code 3');
is($data{country_name}, 'United Kingdom', 'geoip country name');

is($data{area_code}, '', 'geoip area code');
is($data{city_continent_code}, 'EU', 'geoip city continent code');
is($data{city_country_code}, 'GB', 'geoip city country code');
is($data{city_country_code3}, 'GBR', 'geoip city country code 3');
is($data{city_country_name}, 'United Kingdom', 'geoip city country name');
is($data{dma_code}, 826, 'geoip dma code');
is($data{latitude}, 51.5142, 'geoip latitude');
is($data{longitude}, -0.0931, 'geoip longitude');
is($data{region}, 'ENG', 'geoip region');
is($data{region_name}, 'England', 'geoip region name');
is($data{city}, 'London', 'geoip city');
is($data{postal_code}, 'EC1A', 'geoip postal code');

is($data{org}, 'Nginx', 'geoip org');

like(stream_pp('::ffff:81.2.69.160'), qr/org:Nginx/, 'geoip ipv6 ipv4-mapped');

%data = stream_pp('2001:218::') =~ /(\w+):(.*)/g;
is($data{country_code}, 'JP', 'geoip ipv6 country code');
is($data{country_code3}, 'JPN', 'geoip ipv6 country code 3');
is($data{country_name}, 'Japan', 'geoip ipv6 country name');

like(stream_pp('1.128.0.0'), qr/org:Telstra Pty Ltd/, 'geoip mmdb org asorg');
like(stream_pp('::ffff:1.128.0.0'), qr/org:Telstra Pty Ltd/,
	'geoip mmdb ipv4-mapped org ipv4-only db');

%data = stream_pp('10.0.0.1') =~ /(\w+):(.*)/g;
is($data{country_code}, '', 'geoip mmdb private ip - no country code');
is($data{city}, '', 'geoip mmdb private ip - no city');

%data = stream_pp('203.0.113.1') =~ /(\w+):(.*)/g;
is($data{country_code}, 'ZZ', 'geoip mmdb unmapped country code');
is($data{country_code3}, '', 'geoip mmdb unmapped country code 3');

%data = stream_pp('203.0.113.2') =~ /(\w+):(.*)/g;
is($data{country_code}, '', 'geoip mmdb wrong value type');

%data = stream_pp('198.51.100.1') =~ /(\w+):(.*)/g;
is($data{latitude}, '12.5000', 'geoip mmdb float latitude');
is($data{longitude}, '-45.2500', 'geoip mmdb float longitude');
is($data{dma_code}, 500, 'geoip mmdb dma code uint16');

like(stream_pp('198.51.100.2'), qr/dma_code:-5$/m,
	'geoip mmdb dma code int32');

like(stream_pp('1.128.0.1'), qr/org:Example ISP/, 'geoip mmdb org isp');
like(stream_pp('1.128.0.2'), qr/org:Example Organization/,
	'geoip mmdb org organization');
like(stream_pp('1.128.0.3'), qr/org:example.com/, 'geoip mmdb org domain');

%data = stream_pp('198.51.100.3') =~ /(\w+):(.*)/g;
is($data{latitude}, '', 'geoip mmdb float unsupported type');
is($data{longitude}, '', 'geoip mmdb float unsupported type longitude');
is($data{dma_code}, '', 'geoip mmdb int unsupported type');

%data = stream_pp('1.128.0.4') =~ /(\w+):(.*)/g;
is($data{org}, '', 'geoip mmdb org no recognized field');

%data = stream_pp('2001:db8::1') =~ /(\w+):(.*)/g;
is($data{org}, '', 'geoip mmdb org ipv4-only db declines genuine ipv6');

like(stream_pp('1.128.0.5'), qr/org:Telstra Pty Ltd/,
	'geoip mmdb org precedence all fields');
like(stream_pp('1.128.0.6'), qr/org:Example ISP/,
	'geoip mmdb org precedence isp over domain');
like(stream_pp('1.128.0.7'), qr/org:Example ISP/,
	'geoip mmdb org non-string field falls through');

###############################################################################

sub stream_pp {
	my ($ip) = @_;
	my $type = ($ip =~ ':' ? 'TCP6' : 'TCP4');
	return stream('127.0.0.1:' . port(8080))
		->io("PROXY $type $ip 127.0.0.1 8080 8080${CRLF}");
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
