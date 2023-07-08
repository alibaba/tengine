# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 1) + 2;

no_long_string();

worker_connections(1024);
run_tests();

__DATA__

=== TEST 1: simple exit_worker_by_lua_block with hup
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
log from exit_worker_by_lua_block



=== TEST 2: exit after worker_shutdown_timeout
--- main_config
    worker_shutdown_timeout 1;
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
    }

    server {
        listen 12345;

        location = /t {
            echo 'hello world';
        }
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.timer.at(0, function ()
                local sock = ngx.socket.tcp()
                sock:connect("127.0.0.1", 12345)
                local reader = sock:receiveuntil("unknow")
                ngx.log(ngx.NOTICE, "reading to block the exiting")
                reader()
            end)

            ngx.sleep(0)

            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- error_log
reading to block the exiting
--- shutdown_error_log
log from exit_worker_by_lua_block
