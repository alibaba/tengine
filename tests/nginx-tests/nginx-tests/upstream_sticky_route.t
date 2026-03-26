#!/usr/bin/perl

# (C) Nginx, Inc.

# Tests for sticky upstreams ('route' method).

###############################################################################

use warnings;
use strict;

use Test::More;

use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy map rewrite upstream_ip_hash/)
	->has(qw/upstream_sticky/);

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
        listen 127.0.0.1:8086;
        return 444;
    }

    map $cookie_sticky $jsessionid_cookie {
        ~.+\.(?P<key>\w+)$ $key;
    }

    map $request_uri $jsessionid_uri {
        ~jsessionid=.+\.(?P<key>\w+)$ $key;
    }

    map $arg_sticky $resin_arg {
        ~^(?P<key>\w) $key;
    }

    map $request_uri $custom_uri {
        ~sticky=.+\+(?P<key>\w+)\+.+ $key;
    }

    upstream u_sticky_route {

        server 127.0.0.1:8081 route=0;
        server 127.0.0.1:8082 route=1;
        server 127.0.0.1:8083 route=2;
        server 127.0.0.1:8084 route=3;

        sticky route $jsessionid_cookie $jsessionid_uri $resin_arg
                     $custom_uri $arg_all;
    }

    upstream u_sticky_zero_key {

        server 127.0.0.1:8081 route=0;
        server 127.0.0.1:8082 route=1;
        server 127.0.0.1:8083; # server with zero-length key
        server 127.0.0.1:8084 route=3;

        sticky route $arg_sticky;
    }

    upstream u_sticky_route_longnames {

        server 127.0.0.1:8081 route=serverA;
        server 127.0.0.1:8082 route=serverBB;
        server 127.0.0.1:8083 route=serverCCC;
        server 127.0.0.1:8084 route=serverDDDD;

        sticky route $arg_sticky;
    }

    upstream u_sticky_route_no_ids {

        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
        server 127.0.0.1:8083 route=2;
        server 127.0.0.1:8084;

        sticky route $cookie_sticky;
    }

    upstream u_sticky_route_iph {
        ip_hash;

        server 127.0.0.1:8081 route=0;
        server 127.0.0.1:8082 route=1;
        server 127.0.0.1:8083 route=2;
        server 127.0.0.1:8084 route=3;

        sticky route $cookie_sticky;
    }

    upstream u_sticky_route_backup_dead {

        # dead servers
        server 127.0.0.1:8086;
        server 127.0.0.1:8086;

        # alive servers
        server 127.0.0.1:8081 backup route=0;
        server 127.0.0.1:8082 backup route=1;
        server 127.0.0.1:8083 backup route=2;
        server 127.0.0.1:8084 backup route=3;

        sticky route $cookie_sticky;
    }

    upstream u_sticky_route_backup_alive {

        # dead servers
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;

        # alive servers
        server 127.0.0.1:8083 backup route=2;

        sticky route $cookie_sticky;
    }

    upstream u_sticky_route_backup_same {

        # dead servers
        server 127.0.0.1:8086 route=0;
        server 127.0.0.1:8086 route=1;

        # alive servers
        server 127.0.0.1:8081 backup route=0;
        server 127.0.0.1:8082 backup route=1;

        sticky route $cookie_sticky;
    }

    upstream u_sticky_route_bad {

        # 1st sticky server is dead
        server 127.0.0.1:8086 route=0;

        server 127.0.0.1:8082;
        server 127.0.0.1:8081 route=0;

        sticky route $arg_sticky;
    }

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        # to catch incorrect locations in test code
        location / {
            return 502;
        }

        location /sticky_route {
            proxy_pass http://u_sticky_route;
        }

        location ~ /sticky_route_var/(.*) {
            proxy_pass http://u_sticky_route/$1;
        }

        location /sticky_route_longnames {
            proxy_pass http://u_sticky_route_longnames;
        }

        location /sticky_zero_key {
            proxy_pass http://u_sticky_zero_key;
        }

        location /sticky_route_no_ids {
            proxy_pass http://u_sticky_route_no_ids;
        }

        location /sticky_route_iph {
            proxy_pass http://u_sticky_route_iph;
        }

        location /sticky_route_backup_dead {
            proxy_pass http://u_sticky_route_backup_dead;
        }

        location /sticky_route_backup_alive {
            proxy_pass http://u_sticky_route_backup_alive;
        }

        location /sticky_route_backup_same {
            proxy_pass http://u_sticky_route_backup_same;
        }

        location /sticky_route_bad {
            proxy_pass http://u_sticky_route_bad;
        }

        location /var_upstream {
            proxy_pass http://$arg_u;
        }
    }
}

EOF

$t->try_run('no sticky upstream')->plan(48);

###############################################################################

my $response;
my ($port4, $port5) = (port(8084), port(8085));

# new requests get round robin
is_rr('/sticky_route', 4, '0,1,2,3', 'new requests');

# requests without or with empty sticky key get round robin
is_rr('/sticky_route', 4, '0,1,2,3', 'cookie without pattern', 'sticky=xxx',
	'cookie');
is_rr('/sticky_route', 4, '0,1,2,3', 'cookie with zero pattern', 'sticky=xxx.',
	'cookie');

is_rr('/sticky_route', 4, '0,1,2,3', 'arg without pattern', 'sticky=xxx',
	'arg');
is_rr('/sticky_route', 4, '0,1,2,3', 'arg with zero pattern', 'sticky=xxx.',
	'arg');

is_rr('/sticky_route', 4, '0,1,2,3', 'uri without pattern', 'sticky=xxx',
	'uri');
is_rr('/sticky_route', 4, '0,1,2,3', 'uri with zero pattern', 'sticky=xxx.',
	'uri');

# it is ok to have no id for server
is_rr('/sticky_route_no_ids', 4, '0,1,2,3', 'no route', 'sticky=a', 'cookie');

# requests with zero-length key are NOT sticked to servers without keys
is_rr('/sticky_zero_key', 4, '0,1,2,3', 'zero-length key', 'sticky=', 'uri');

# requests with correct sticky keys go to appropriate backends
for my $k (0 .. 3) {
	is_sticky('/sticky_route', "sticky=xxx.$k", 'cookie', $k, 'jvmroute');
	is_sticky('/sticky_route', "sticky=$k.xxx", 'arg', $k, 'resin');
	is_sticky('/sticky_route', "sticky=xxx+$k+xxx", 'uri', $k, 'regex');
	is_sticky('/sticky_route', "all=$k", 'arg', $k, 'all(implicit)');
	is_sticky('/sticky_route_iph', "sticky=$k", 'cookie', $k, 'IP hash');
}

is_sticky('/sticky_route_longnames', "sticky=serverA", 'arg', 0,
	'Long name serverA');
is_sticky('/sticky_route_longnames', "sticky=serverBB", 'arg', 1,
	'Long name serverBB');
is_sticky('/sticky_route_longnames', "sticky=serverCCC", 'arg', 2,
	'Long name serverCCC');
is_sticky('/sticky_route_longnames', "sticky=serverDDDD", 'arg', 3,
	'Long name serverDDDD');

for my $k (0 .. 3) {
	is_sticky('/sticky_route_var/', "sticky=xxxxx.$k", 'cookie', $k,
		'upstream with variables');
	is_sticky('/var_upstream?u=u_sticky_route', "sticky=xxxxx.$k",
		'cookie', $k, 'variable upstream');
}

# single server with id among those without, is accessible by id
is_sticky('/sticky_route_no_ids', 'sticky=2', 'cookie', 2, 'single route');

# first specified property has priority, others ignored
is_sticky('/sticky_route;sticky=xxx.2?sticky=3.xxxx', 'sticky=xxxxx.1',
	'cookie', 1, 'Cookie priority');
is_sticky('/sticky_route;sticky=xxx.2', 'sticky=3.xxxx', 'arg', 3,
	'Argument priority');

TODO: {
local $TODO = 'not yet';

# if there are multiple servers with the same route, peer should be selected
# among them before falling back to upstream balancer
is_sticky('/sticky_route_bad', "sticky=0", 'arg', 0, 'sticky after bad peer');

}

# backup servers

# if primary servers are dead, backup server can be reached by id
is_sticky('/sticky_route_backup_dead', 'sticky=2', 'cookie', 2,
	'backup in dead upstream by id');

# if there are alive primary servers, backup server is not reached by id
is_rr('/sticky_route_backup_alive', 2, '0,1', 'backup in alive upstream',
	'sticky=2', 'cookie');

# if there are primary servers with same id as in backup, alive are chosen
is_sticky('/sticky_route_backup_same', 'sticky=1', 'cookie', 1,
	'backup in alive upstream');

###############################################################################

sub is_rr {
	my ($uri, $backends_cnt, $pattern, $title, $key, $key_method) = @_;

	my $num = $backends_cnt * 4;

	my @act_replies;

	@act_replies = map { get_backend($uri, $key, $key_method) } (1 .. $num);

	my $act = join(",", @act_replies);
	my $exp = join(",", map { $pattern } (1..4));

	is($act, $exp, "$title: round-robin");
}

sub is_sticky {
	my ($uri, $key, $key_method, $exp_backend, $title) = @_;

	my $num = 10;

	my $act_replies = join ' ',
		map { get_backend($uri, $key, $key_method) } (1 .. $num);
	my $exp_replies = join ' ', map { $exp_backend } (1 .. $num);

	is($act_replies, $exp_replies,
		"$title: request to '$exp_backend' with '$key' is sticky");
}

sub get_backend {
	my ($uri, $key, $key_method) = @_;

	my $backend;

	if (!defined($key)) {
		return get_backend_by_uri($uri);
	}

	if ($key_method eq 'cookie') {
		($backend) = get_backend_by_cookie($uri, "$key");

	} elsif ($key_method eq 'arg') {
		($backend) = get_backend_by_uri("$uri?$key");

	} elsif ($key_method eq 'uri') {
		($backend) = get_backend_by_uri("$uri;$key");
	}

	return $backend;
}

sub get_backend_by_uri {
	my ($uri) = @_;
	my ($backend) = http_get($uri) =~ /backend_(\d+)/;
	return $backend;
}

sub get_backend_by_cookie {
	my ($uri, $cookie) = @_;

	my $request=<<EOF;
GET $uri HTTP/1.1
Host: localhost
Connection: close
Cookie: $cookie

EOF

	my ($backend) = http($request) =~ /backend_(\d+)/;
	return $backend;
}

###############################################################################
