# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

log_level('info');
repeat_each(1);

plan tests => repeat_each() * (blocks() * 6);

my $pwd = cwd();

no_long_string();

check_accum_error_log();
run_tests();

__DATA__

=== TEST 1: sanity
--- http_config
    lua_shared_dict request_counter 1m;
    upstream my_upstream {
        server 127.0.0.1;
        balancer_by_lua_block {
            local balancer = require "ngx.balancer"

            if not ngx.ctx.tries then
                ngx.ctx.tries = 0
            end

            ngx.ctx.tries = ngx.ctx.tries + 1
            ngx.log(ngx.INFO, "tries ", ngx.ctx.tries)

            if ngx.ctx.tries == 1 then
                balancer.set_more_tries(5)
            end

            local host = "127.0.0.1"
            local port = $TEST_NGINX_RAND_PORT_1;

            local ok, err = balancer.set_current_peer(host, port)
            if not ok then
                ngx.log(ngx.ERR, "failed to set the current peer: ", err)
                return ngx.exit(500)
            end

            balancer.set_timeouts(60000, 60000, 60000)

            local ok, err = balancer.enable_keepalive(60, 100)
            if not ok then
                ngx.log(ngx.ERR, "failed to enable keepalive: ", err)
                return ngx.exit(500)
            end
        }
    }

    server {
        listen 127.0.0.1:$TEST_NGINX_RAND_PORT_1;
        location /hello {
            content_by_lua_block{
                local request_counter = ngx.shared.request_counter
                local first_request = request_counter:get("first_request")
                if first_request == nil then
                    request_counter:set("first_request", "yes")
                    ngx.print("hello")
                else
                    ngx.exit(ngx.HTTP_CLOSE)
                end
            }
        }
    }
--- config
    location = /t {
        proxy_pass http://my_upstream;
        proxy_set_header Connection "keep-alive";

        rewrite_by_lua_block {
           ngx.req.set_uri("/hello")
        }
    }
--- pipelined_requests eval
["GET /t HTTP/1.1" , "GET /t HTTP/1.1"]
--- response_body eval
["hello", qr/502/]
--- error_code eval
[200, 502]
--- no_error_log eval
qr/tries 7/
