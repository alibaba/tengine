# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

$ENV{TEST_NGINX_MY_INIT_CONFIG} = <<_EOC_;
lua_package_path "t/lib/?.lua;;";
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: turning a peer up should also clear fails
--- http_config
    upstream foo.com {
        server 127.0.0.1:12345 max_fails=3;
        server 127.0.0.1:12346 max_fails=3;
    }

    server {
        server_name foo.com;
        listen 12345;
        listen 12346;

        location / {
            return 444;
        }
    }

--- config
    location /t {
        content_by_lua_block {
			for i = 1, 3 do
				ngx.location.capture("/sub")
			end
            local upstream = require "ngx.upstream"
            local res = upstream.get_primary_peers("foo.com")
            ngx.say(res[1].fails)
            assert(upstream.set_peer_down("foo.com", false, 0, false))
            res = upstream.get_primary_peers("foo.com")
            ngx.say(res[1].fails)
        }
    }

    location /sub {
        proxy_pass http://foo.com;
    }
--- request
GET /t
--- response_body
3
0
--- no_error_log
[alert]
