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

use lib 'lib';
use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason) : ();

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
no_long_string();
#master_on();
#workers(2);

no_shuffle();

run_tests();

__DATA__

=== TEST 1: get_info, before HUP reload
--- http_config
    lua_fake_shm x1 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            local name, size, isinit, isold
            local x1 = shm_zones.x1

            name, size, isinit, isold = x1:get_info()
            ngx.say("name=", name)
            ngx.say("size=", size)
            ngx.say("isinit=", isinit)
            ngx.say("isold=", isold)
        }
    }
--- request
GET /test
--- response_body
name=x1
size=1048576
isinit=true
isold=false
--- no_error_log
[error]



=== TEST 2: get_info, after HUP reload
--- http_config
    lua_fake_shm x1 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            local name, size, isinit, isold
            local x1 = shm_zones.x1

            name, size, isinit, isold = x1:get_info()
            ngx.say("name=", name)
            ngx.say("size=", size)
            ngx.say("isinit=", isinit)
            ngx.say("isold=", isold)
        }
    }
--- request
GET /test
--- response_body
name=x1
size=1048576
isinit=true
isold=true
--- no_error_log
[error]
