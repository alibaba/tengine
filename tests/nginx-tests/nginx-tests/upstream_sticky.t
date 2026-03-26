#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams (cookie mode).

###############################################################################

use warnings;
use strict;

use Test::More;
use Time::Local;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http http_ssl proxy rewrite upstream_sticky/)
	->has(qw/upstream_ip_hash upstream_least_conn upstream_keepalive map/)
	->has_daemon('openssl');

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen 127.0.0.1:8081;
        location / {
            add_header X-Connection $connection;
            return 200 "backend_0";
        }
    }

    server {
        listen 127.0.0.1:8082;
        location / {
            return 200 "backend_1";
        }
    }

    server {
        listen 127.0.0.1:8083;
        location / {
            return 200 "backend_2";
        }
    }

    server {
        listen 127.0.0.1:8084;
        location / {
            return 200 "backend_3";
        }
    }

    server {
        listen 127.0.0.1:8085 ssl;

        ssl_certificate_key localhost.key;
        ssl_certificate localhost.crt;

        location / {
            return 200 "backend_ssl";
        }
    }

    server {
        listen 127.0.0.1:8086;
        location / {
            return 502 "backend_4";
        }
    }

    upstream u_backend_0 {
        server 127.0.0.1:8081;
        sticky cookie "sticky";
    }

    upstream u_backend_1 {
        server 127.0.0.1:8082;
        sticky cookie "sticky";
    }

    upstream u_backend_2 {
        server 127.0.0.1:8083;
        sticky cookie "sticky";
    }

    upstream u_backend_3 {
        server 127.0.0.1:8084;
        sticky cookie "sticky";
    }

    upstream u_backend_ssl {
        server 127.0.0.1:8085;
        sticky cookie "sticky";
    }

    upstream u_backend_4 {
        server 127.0.0.1:8086;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky_w {
        server 127.0.0.1:8081 weight=1;
        server 127.0.0.1:8082 weight=2;
        server 127.0.0.1:8083 weight=3;
        server 127.0.0.1:8084 weight=4;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky_ka {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        keepalive 10;
        sticky cookie "sticky";
    }

    upstream u_rr_sticky_ka_r {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        sticky cookie "sticky";
        keepalive 10;
    }

    upstream u_lc_sticky {
        least_conn;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        sticky cookie "sticky_lc";
    }

    upstream u_iph_sticky {
        ip_hash;
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        sticky cookie "sticky_iph";
    }

    upstream u_rr_sticky_cookie_fields {
        server 127.0.0.1:8081;
        sticky cookie sticky domain=example.com path=/ "expires=1h 3m"
                             secure httponly samesite=lax;
    }

    upstream u_rr_sticky_path_only {
        server 127.0.0.1:8081;
        sticky cookie sticky path=/test/path;
    }

    upstream u_rr_sticky_domain_only {
        server 127.0.0.1:8081;
        sticky cookie sticky domain=localhost;
    }

    upstream u_rr_sticky_domain_cv {
        server 127.0.0.1:8081;
        sticky cookie sticky domain=$arg_v$arg_v2;
    }

    upstream u_rr_sticky_expires_max {
        server 127.0.0.1:8081;
        sticky cookie sticky expires=max;
    }

    upstream u_rr_sticky_expires_value {
        server 127.0.0.1:8081;
        sticky cookie sticky expires=60m;
    }

    upstream u_rr_sticky_secure_only {
        server 127.0.0.1:8081;
        sticky cookie sticky secure;
    }

    upstream u_rr_sticky_httponly_only {
        server 127.0.0.1:8081;
        sticky cookie sticky httponly;
    }

    upstream u_rr_sticky_samesite_lax_only {
        server 127.0.0.1:8081;
        sticky cookie sticky samesite=lax;
    }

    upstream u_rr_sticky_samesite_strict_only {
        server 127.0.0.1:8081;
        sticky cookie sticky samesite=strict;
    }

    upstream u_rr_sticky_samesite_none_only {
        server 127.0.0.1:8081;
        sticky cookie sticky samesite=none;
    }

    upstream u_rr_sticky_samesite_var {
        server 127.0.0.1:8081;
        sticky cookie sticky samesite=$samesite;
    }

    upstream u_sticky_with_down {
        # good servers
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 down;
        server 127.0.0.1:8084 down;
        sticky cookie sticky;
    }

    upstream u_pnu {
        # bad server
        server 127.0.0.1:8086 max_fails=2;
        # good servers
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        sticky cookie sticky;
    }

    upstream u_var_1 {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        sticky cookie s_var_1;
    }

    upstream u_var_2 {
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
        sticky cookie s_var_2;
    }

    # no alive peers
    upstream u_sticky_dead {
        server 127.0.0.1:8081 down;
        sticky cookie sticky;
    }

    upstream u_no_sticky {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083;
        server 127.0.0.1:8084;
    }

    map $args $conn {
        default  close;
        keep     keep-alive;
    }

    map $arg_a $samesite {
        default  $arg_a;
        empty    "";
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # to catch incorrect locations in test code
        location / {
            return 502;
        }

        # to access the single backend definitely with sticky
        location /backend_0 {
            proxy_pass http://u_backend_0;
        }
        location /backend_1 {
            proxy_pass http://u_backend_1;
        }
        location /backend_2 {
            proxy_pass http://u_backend_2;
        }
        location /backend_3 {
            proxy_pass http://u_backend_3;
        }
        location /backend_4 {
            proxy_pass http://u_backend_4;
        }

        location /rr_sticky {
            proxy_pass http://u_rr_sticky;
        }

        location /rr_sticky_w {
            proxy_pass http://u_rr_sticky_w;
        }

        location ~ /rr_sticky_var/(.*) {
            proxy_pass http://u_rr_sticky/$1;
        }

        location /rr_sticky_ka {
            proxy_pass http://u_rr_sticky_ka;
            proxy_http_version 1.1;
            proxy_set_header Connection $conn;
        }

        location /rr_sticky_ka_r {
            proxy_pass http://u_rr_sticky_ka_r;
            proxy_http_version 1.1;
            proxy_set_header Connection $conn;
        }

        location /lc_sticky {
            proxy_pass http://u_lc_sticky;
        }

        location /iph_sticky {
            proxy_pass http://u_iph_sticky;
        }

        location /rr_sticky_cookie_fields {
            proxy_pass http://u_rr_sticky_cookie_fields;
        }

        location /rr_sticky_path_only {
            proxy_pass http://u_rr_sticky_path_only;
        }

        location /rr_sticky_domain_only {
            proxy_pass http://u_rr_sticky_domain_only;
        }

        location /rr_sticky_domain_cv {
            proxy_pass http://u_rr_sticky_domain_cv;
        }

        location /rr_sticky_expires_max {
            proxy_pass http://u_rr_sticky_expires_max;
        }

        location /rr_sticky_expires_value {
            proxy_pass http://u_rr_sticky_expires_value;
        }

        location /rr_sticky_secure_only {
            proxy_pass http://u_rr_sticky_secure_only;
        }

        location /rr_sticky_httponly_only {
            proxy_pass http://u_rr_sticky_httponly_only;
        }

        location /rr_sticky_samesite_lax_only {
            proxy_pass http://u_rr_sticky_samesite_lax_only;
        }

        location /rr_sticky_samesite_strict_only {
            proxy_pass http://u_rr_sticky_samesite_strict_only;
        }

        location /rr_sticky_samesite_none_only {
            proxy_pass http://u_rr_sticky_samesite_none_only;
        }

        location /rr_sticky_samesite_var {
            proxy_pass http://u_rr_sticky_samesite_var;
        }

        location /rr_sticky_with_down {
            proxy_pass http://u_sticky_with_down;
        }

        location /rr_sticky_dead {
            proxy_pass http://u_sticky_dead;
        }

        location /no_sticky {
            proxy_pass http://u_no_sticky;
        }

        location /sticky_ssl {
            proxy_pass https://u_backend_ssl;
        }

        location /pnu {
            proxy_pass http://u_pnu;
            proxy_next_upstream http_502;
        }

        location /var {
            proxy_pass http://$arg_u;
        }
    }
}

EOF

$t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 2048
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

$t->try_run('no sticky upstream')->plan(183);

###############################################################################

my (%backend_cookies, $r, $r2);

# record cookies returned by each backend server for use in tests
collect_backend_cookies(4, 'sticky', \%backend_cookies);

# verify sticky with round-robin balancer
basic_tests('/rr_sticky', 'sticky', \%backend_cookies);
# verify sticky with least_conn balancer
basic_tests('/lc_sticky', 'sticky_lc', \%backend_cookies);
# verify sticky with IP hash balancer
basic_tests('/iph_sticky', 'sticky_iph', \%backend_cookies);
# verify sticky with location using variables for upstream
basic_tests('/rr_sticky_var/', 'sticky', \%backend_cookies);
# verify sticky with keep-alive on
basic_tests('/rr_sticky_ka', 'sticky', \%backend_cookies);
# verify sticky directives in reverse order with keep-alive
basic_tests('/rr_sticky_ka_r', 'sticky', \%backend_cookies);

# sane keepalive connection and set-cookie
$r = sticky_request_ka('/rr_sticky_ka_r?keep', 0, \%backend_cookies);
$r2 = sticky_request_ka('/rr_sticky_ka_r?keep', 0, \%backend_cookies);
ok($r->{conn}, 'rr_sticky_ka_r connection');
is($r2->{conn}, $r->{conn}, 'rr_sticky_ka_r connection keepalive');
ok($r->{cookie}, 'rr_sticky_ka_r cookie');
is($r2->{cookie}, $r->{cookie}, 'rr_sticky_ka_r cookie keepalive');

$r = sticky_request_ka('/rr_sticky_ka?keep', 0, \%backend_cookies);
$r2 = sticky_request_ka('/rr_sticky_ka?keep', 0, \%backend_cookies);
ok($r->{conn}, 'rr_sticky_ka connection');
is($r2->{conn}, $r->{conn}, 'rr_sticky_ka connection keepalive');
ok($r->{cookie}, 'rr_sticky_ka cookie');
is($r2->{cookie}, $r->{cookie}, 'rr_sticky_ka cookie keepalive');

# miscellaneous tests
misc_tests('sticky', \%backend_cookies);

# tests for correctness of cookie contents

# nginx.conf has: "expires=1h 3m";
my $cookie_expires_expected = time() + 3600 + 3 * 60;

my $cookie_hash = get_cookie_hash('/rr_sticky_cookie_fields');
ok($cookie_hash, 'cookie');

SKIP: {
skip 'cannot parse cookie', 12 unless $cookie_hash;

ok(defined($cookie_hash->{'domain'}), "cookie has 'domain' field");
ok(defined($cookie_hash->{'path'}), "cookie has 'path' field");
ok(defined($cookie_hash->{'expires'}), "cookie has 'expires' field");
ok(defined($cookie_hash->{'max-age'}), "cookie has 'max-age' field");
ok(exists($cookie_hash->{'secure'}), "cookie has 'secure' field");
ok(exists($cookie_hash->{'httponly'}), "cookie has 'httponly' field");
is($cookie_hash->{'samesite'}, 'lax', "cookie has 'samesite=lax' field");
is($cookie_hash->{'domain'}, 'example.com', 'domain is correct');
is($cookie_hash->{'path'}, '/', 'path is correct');
is($cookie_hash->{'max-age'}, 3780, 'max-age is correct');

my $cookie_expires_act = parse_cookie_time($cookie_hash->{'expires'});
ok(defined($cookie_expires_act), 'expire time has correct format');

# let the time in cookie differ by 10 seconds on calculated
# expectation prior to the request was made
ok(abs($cookie_expires_expected - $cookie_expires_act) <= 10,
	'expire time is set properly');

}

# only domain
$cookie_hash = get_cookie_hash('/rr_sticky_domain_only');
ok($cookie_hash, 'only domain');

SKIP: {
skip 'cannot parse cookie', 8 unless $cookie_hash;

ok(defined($cookie_hash->{'domain'}), "cookie has 'domain' field");
is($cookie_hash->{'domain'}, 'localhost', "cookie 'domain' field is ok");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!defined($cookie_hash->{'max-age'}), "cookie has no 'max-age' field");
ok(!defined($cookie_hash->{'samesite'}), "cookie has no 'samesite' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");

}

# domain with complex value
$cookie_hash = get_cookie_hash('/rr_sticky_domain_cv?v=foo');
ok($cookie_hash, 'domain with complex value');

SKIP: {
skip 'cannot parse cookie', 2 unless $cookie_hash;

ok(defined($cookie_hash->{'domain'}), "cookie has 'domain' cv");
is($cookie_hash->{'domain'}, 'foo', "cookie 'domain' cv is ok");

}

$cookie_hash = get_cookie_hash('/rr_sticky_domain_cv?v=bar&v2=baz');
ok($cookie_hash, 'domain with complex value 2');

SKIP: {
skip 'cannot parse cookie', 2 unless $cookie_hash;

ok(defined($cookie_hash->{'domain'}), "cookie has 'domain' cv2");
is($cookie_hash->{'domain'}, 'barbaz', "cookie 'domain' cv2 is ok");

}

$cookie_hash = get_cookie_hash('/rr_sticky_domain_cv');
ok($cookie_hash, 'domain with complex value 3');

SKIP: {
skip 'cannot parse cookie', 1 unless $cookie_hash;

ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' cv");

}

# only path
$cookie_hash = get_cookie_hash('/rr_sticky_path_only');
ok($cookie_hash, 'only path');

SKIP: {
skip 'cannot parse cookie', 7 unless $cookie_hash;

ok(defined($cookie_hash->{'path'}), "cookie has 'path' field");
is($cookie_hash->{'path'}, '/test/path', "cookie 'path' field is ok");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!defined($cookie_hash->{'samesite'}), "cookie has no 'samesite' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");

}

# only expires (max)
$cookie_hash = get_cookie_hash('/rr_sticky_expires_max');
ok($cookie_hash, 'only expires');

SKIP: {
skip 'cannot parse cookie', 9 unless $cookie_hash;

ok(defined($cookie_hash->{'expires'}), "cookie has 'expires' field set");
ok(defined($cookie_hash->{'max-age'}), "cookie has 'max-age' field set");
is($cookie_hash->{'expires'}, 'Thu, 31-Dec-37 23:55:55 GMT',
	"cookie 'expires' is set properly to maximum date");
is($cookie_hash->{'max-age'}, 315360000, "cookie 'max-age' is 10 years");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'samesite'}), "cookie has no 'samesite' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");

}

# only secure
$cookie_hash = get_cookie_hash('/rr_sticky_secure_only');
ok($cookie_hash, 'only secure');

SKIP: {
skip 'cannot parse cookie', 6 unless $cookie_hash;

ok(exists($cookie_hash->{'secure'}), "cookie has 'secure' field");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!defined($cookie_hash->{'samesite'}), "cookie has no 'samesite' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");

}

# only httponly
$cookie_hash = get_cookie_hash('/rr_sticky_httponly_only');
ok($cookie_hash, 'only httponly');

SKIP: {
skip 'cannot parse cookie', 6 unless $cookie_hash;

ok(exists($cookie_hash->{'httponly'}), "cookie has 'httponly' field");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!defined($cookie_hash->{'samesite'}), "cookie has no 'samesite' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");

}

# only samesite=lax
$cookie_hash = get_cookie_hash('/rr_sticky_samesite_lax_only');
ok($cookie_hash, 'only samesite=lax');

SKIP: {
skip 'cannot parse cookie', 6 unless $cookie_hash;

is($cookie_hash->{'samesite'}, 'lax', "cookie has 'samesite=lax' field");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");

}

# only samesite=strict
$cookie_hash = get_cookie_hash('/rr_sticky_samesite_strict_only');
ok($cookie_hash, 'only samesite=strict');

SKIP: {
skip 'cannot parse cookie', 6 unless $cookie_hash;

is($cookie_hash->{'samesite'}, 'strict', "cookie has 'samesite=strict' field");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");

}

# only samesite=none
$cookie_hash = get_cookie_hash('/rr_sticky_samesite_none_only');
ok($cookie_hash, 'only samesite=none');

SKIP: {
skip 'cannot parse cookie', 6 unless $cookie_hash;

is($cookie_hash->{'samesite'}, 'none', "cookie has 'samesite=none' field");
ok(!defined($cookie_hash->{'path'}), "cookie has no 'path' field");
ok(!defined($cookie_hash->{'domain'}), "cookie has no 'domain' field");
ok(!defined($cookie_hash->{'expires'}), "cookie has no 'expires' field");
ok(!exists($cookie_hash->{'httponly'}), "cookie has no 'httponly' field");
ok(!exists($cookie_hash->{'secure'}), "cookie has no 'secure' field");

}

# samesite=$variable
is(get_cookie_hash('/rr_sticky_samesite_var?a=strict')->{'samesite'},
	'strict', 'variable samesite=strict');
is(get_cookie_hash('/rr_sticky_samesite_var?a=none')->{'samesite'},
	'none', 'variable samesite=none');
is(get_cookie_hash('/rr_sticky_samesite_var?a=lax')->{'samesite'},
	'lax', 'variable samesite=lax');
is(get_cookie_hash('/rr_sticky_samesite_var?a=wrong')->{'samesite'},
	'strict', 'variable samesite default');
ok(!defined(get_cookie_hash('/rr_sticky_samesite_var?a=empty')->{'samesite'}),
	'variable samesite empty, ignored');

# verify that balancers work properly after adding sticky
regression_tests(\%backend_cookies);

like(http_get('/sticky_ssl'), qr/200 OK.*^backend_ssl$/sm, 'ssl');

###############################################################################

# walk through all backends (each is the only in own upstream) to get
# its cookies
sub collect_backend_cookies {
	my ($server_cnt, $cookie_name, $backend_cookies) = @_;

	my ($response, $backend, $cookie);

	for my $n (0 .. ($server_cnt - 1)) {
		my $uri = '/backend_'.$n;
		$response = http_get($uri);

		($backend) = $response =~ /backend_(\d+)/;
		($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

		# We expect only good 'backend_N' responses
		if (!defined($backend)) {
			fail("request to '$uri' returned unexpected response");
			return;
		}

		# Each response must have a cookie set
		if (!defined($cookie)) {
			fail("request to '$uri' has no cookie '$cookie_name'");
			return;
		}
		$backend_cookies->{$backend} = $cookie;
	}
}

sub regression_tests {
	my ($backend_cookies) = @_;

	# verify that round-robin still works in sticky upstreams
	# (for new requests)
	verify_rr_distribution('/rr_sticky', 20, [1, 1, 1, 1]);
	verify_rr_distribution('/rr_sticky_w', 100, [1, 2, 3, 4]);

	# disbalance weights with sticky requests to the first backend
	# and verify distribution after

	for (1 .. 20) {
		sticky_request('/rr_sticky', 0, $backend_cookies, 'sticky');
	}
	verify_rr_distribution('/rr_sticky', 20, [1, 1, 1, 1]);

	for (1 .. 100) {
		sticky_request('/rr_sticky_w', 0, $backend_cookies, 'sticky');
	}
	verify_rr_distribution('/rr_sticky_w', 100, [1, 2, 3, 4]);
}


sub basic_tests {
	my ($uri, $cookie_name, $backend_cookies) = @_;

	my ($response, $backend, $cookie);

	# Requests with sticky cookies must be processed by corresponding
	# backends
	for my $key (keys(%$backend_cookies)) {
		$response = sticky_request($uri, $key, $backend_cookies,
			$cookie_name);
		($backend) = $response =~ /backend_(\d+)/;
		is($backend, $key, "request to server $key in $uri");

		# now sticky cookie always presents in the response
		($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;
		is($cookie, $backend_cookies->{$key},
			'sticky cookie always set');
	}

	# Request with bad cookie gets a new one, corresponding to backend,
	# which processed the request
	my %bad_cookies = ( '0' => '012345689.123456789.123456789.12-too-big' );
	$response = sticky_request($uri, 0, \%bad_cookies, $cookie_name);

	($backend) = $response =~ /backend_(\d+)/;
	($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	is($cookie, $backend_cookies->{$backend},
		"new cookie is set if client cookie is too big in $uri");

	# same, but cookie length does not exceed limit
	%bad_cookies = ( '0' => 'garbage' );
	$response = sticky_request($uri, 0, \%bad_cookies, $cookie_name);

	($backend) = $response =~ /backend_(\d+)/;
	($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	is($cookie, $backend_cookies->{$backend},
		"new cookie is set if client cookie is garbage in $uri");
}


sub misc_tests {
	my ($cookie_name, $backend_cookies) = @_;

	my ($response, $backend, $cookie);

	($cookie) = http_get('/no_sticky') =~ /Set-Cookie: $cookie_name=(.*)/;
	ok(!defined($cookie), "no sticky cookies for non-sticky upstream");

	# Sticky request to a backend marked as down => new cookie expected
	$response = sticky_request('/rr_sticky_with_down', 3, $backend_cookies,
		$cookie_name);

	($backend) = $response =~ /backend_(\d+)/;
	($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	is($cookie, $backend_cookies->{$backend},
		'new cookie is set if requested server is \'down\'');

	# Stress test: request to dead upstream, expecting to get 500 without
	# sticky cookies

	$response = sticky_request('/rr_sticky_dead', 0, $backend_cookies,
		$cookie_name);

	($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	ok(!defined($cookie), 'no cookie for dead upstream');
	like($response, "/HTTP\/1.1 502 Bad Gateway/",
		'502 is returned for dead upstream');

	# proxy_next_upstream test

	# prepare for test: get cookie for backend 4 that returns 502
	($cookie, $backend) = http_get_sticky_reply("/backend_4", $cookie_name);
	$backend_cookies->{$backend} = $cookie;

	# test itself
	# backends response order: 4(502), 0(200), 1(200), 2(200)

	# 1st normal request to upstream: will get 502 from 4, then 200 from 0
	($cookie, $backend) = http_get_sticky_reply("/pnu", $cookie_name);

	is($backend, "0", "new request switched to next upstream");
	is($cookie, $backend_cookies{0},
		'sticky cookie is ok for next upstream');

	# sticky request to 4: will get 502 from 4, then 200 from 1
	$response = sticky_request('/pnu', 4, $backend_cookies,
		$cookie_name);

	($backend) = $response =~ /backend_(\d+)/;
	($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	is($backend, "1", "sticky request switched to next upstream");
	is($cookie, $backend_cookies{1},
		'sticky cookie is ok for next upstream');

	# verify that sticky uses correct upstream configuration if upstream
	# is selected at runtime

	($cookie, $backend) = http_get_sticky_reply("/var?u=u_var_1",
		"s_var_1");
	ok(defined($cookie), "cookie name is correct for upstream 1");

	($cookie, $backend) = http_get_sticky_reply("/var?u=u_var_2",
		"s_var_2");
	ok(defined($cookie), "cookie name is correct for upstream 2");
}

###############################################################################

# converts formatted time into number of seconds since epoch
sub parse_cookie_time {
	my ($date) = @_;

	my ($day, $month, $year, $h, $m, $s);

	my %months = ( "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4,
		"May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
		"Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12 );

	# Example date: 'Thu, 28-Feb-13 08:50:04 GMT'
	if ($date =~ /^\w+\,\s+(\d+)-(\w+)-(\d+)\s+(\d+):(\d+):(\d+)\s+GMT$/) {
		($day, $month, $year, $h, $m, $s) =
		($1, $months{$2}, $3, $4, $5, $6);

	} else {
		return undef;
	}

	# months are enumerated from zero
	return timegm($s, $m, $h, $day, $month - 1, $year);
}


# extracts cookie's name/value pairs into hash
sub get_cookie_hash {
	my ($uri) = @_;

	my (@pair, @pairs);
	my %cookie_hash;

	my ($cookie_str) = http_get_sticky_reply($uri, 'sticky');

	if (!defined($cookie_str) || $cookie_str eq '') {
		return undef;
	}

	# split cookie fields into array of 'name=value' tokens
	@pairs = split(';', $cookie_str);
	if (scalar @pairs == 0) {
		return undef;
	}

	# remove leading/trailing spaces from each pair
	map { $_ =~ s/^\s+// } @pairs;
	map { $_ =~ s/\s+$// } @pairs;

	# create hash from all pairs
	foreach (@pairs) {
		@pair = split(/=/, $_);
		$cookie_hash{lc($pair[0])} = $pair[1];
	}

	return \%cookie_hash;
}


# sends sticky request to particular backend
sub sticky_request {
	my ($uri, $backend_index, $backend_cookies, $cookie_name) = @_;

	my $cookie = $cookie_name.'='.$backend_cookies->{$backend_index};

	my $request=<<EOF;
GET $uri HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF

	return http($request);
}


sub sticky_request_ka {
	my ($uri, $backend_index, $backend_cookies) = @_;

	my $cookie = 'sticky='.$backend_cookies->{$backend_index};

	my $response = http(<<EOF);
GET $uri HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF

	my ($connection) = $response =~ /X-Connection: (\d+)/;
	($cookie) = $response =~ /Set-Cookie: sticky=(.*)/;

	return {conn => $connection, cookie => $cookie};
}


sub http_get_sticky_reply {
	my ($uri, $cookie_name) = @_;

	my $response = http_get($uri);

	my ($backend) = $response =~ /backend_(\d+)/;
	my ($cookie) = $response =~ /Set-Cookie: $cookie_name=(.*)/;

	return ($cookie, $backend);
}


sub verify_rr_distribution {
	my ($uri, $rcnt, $server_weights) = @_;

	my $total_w = 0;
	foreach my $weight (@$server_weights) {
		$total_w += $weight;
	}

	# Prepare:
	#
	# perform $rcnt requests to specified $uri and save number of
	# responses from each backend.

	my %resp_count_hash;

	for my $k (1 .. $rcnt) {
		my ($backend) = http_get($uri) =~ /backend_(\d+)/;

		if (!defined($backend)) {
			fail("request N '$k' to '$uri': unexpected response");
			return;
		}
		$resp_count_hash{$backend}++;
	}

	# Compare collected data with expected results

	my $actual;   # number of requests actually processed by this backend
	my $expected; # number of requests we expect for particular backend

	foreach my $key (sort keys(%resp_count_hash)) {

		$actual = $resp_count_hash{$key};
		$expected = (@$server_weights[$key] * $rcnt) / $total_w;

		my $msg = sprintf("server %d got %2d requests of %3d total, ".
			"%3d expected in '%s'", $key, $actual, $rcnt,
			$expected, $uri);

		ok(abs($actual - $expected) <= 1, $msg);
	}
}

###############################################################################
