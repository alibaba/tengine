# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 - 1);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: require test
--- http_config
    lua_fake_shm x1 1m;
    lua_fake_shm x2 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            ngx.say(type(shm_zones))
            local x1 = shm_zones.x1
            ngx.say(type(x1))
            local x2 = shm_zones.x2
            ngx.say(type(x1))
        }
    }
--- request
GET /test
--- response_body
table
table
table
--- no_error_log
[error]



=== TEST 2: index shm_zone
--- http_config
    lua_fake_shm x1 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            local x1 = shm_zones.x1
            ngx.say(type(x1))
        }
    }
--- request
GET /test
--- response_body
table
--- no_error_log
[error]



=== TEST 3: get_info
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



=== TEST 4: multiply zones
--- http_config
    lua_fake_shm x1 1m;
    lua_fake_shm x2 2m;
    lua_fake_shm x3 3m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            local name, size, isinit, isold
            local x1 = shm_zones.x1
            local x2 = shm_zones.x2
            local x3 = shm_zones.x3

            name, size, isinit, isold = x1:get_info()
            ngx.say("name=", name)
            ngx.say("size=", size)
            ngx.say("isinit=", isinit)
            ngx.say("isold=", isold)

            name, size, isinit, isold = x2:get_info()
            ngx.say("name=", name)
            ngx.say("size=", size)
            ngx.say("isinit=", isinit)
            ngx.say("isold=", isold)

            name, size, isinit, isold = x3:get_info()
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
name=x2
size=2097152
isinit=true
isold=false
name=x3
size=3145728
isinit=true
isold=false
--- no_error_log
[error]



=== TEST 5: duplicate zones
--- http_config
    lua_fake_shm x1 1m;
    lua_fake_shm x1 1m;
--- config
    location = /test {
        content_by_lua_block {
            local shm_zones = require("fake_shm_zones")
            local x1 = shm_zones.x1
            ngx.say("error")
        }
    }
--- request
GET /test
--- request_body_unlike
error
--- must_die
--- error_log
lua_fake_shm "x1" is already defined as "x1"
--- error_log
[emerg]
