# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

master_on();
repeat_each(2);

# NB: the shutdown_error_log block is independent from repeat times
plan tests => repeat_each() * (blocks() * 2 + 1) + 15;

#log_level("warn");
no_long_string();
our $HtmlDir = html_dir;

run_tests();

__DATA__

=== TEST 1: simple exit_worker_by_lua_block
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_block")
    }
--- config
    location /t {
        echo "ok";
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
log from exit_worker_by_lua_block



=== TEST 2: simple exit_worker_by_lua_file
--- http_config
    exit_worker_by_lua_file html/exit_worker.lua;
--- config
    location /t {
        echo "ok";
    }
--- user_files
>>> exit_worker.lua
ngx.log(ngx.NOTICE, "log from exit_worker_by_lua_file")
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
log from exit_worker_by_lua_file



=== TEST 3: exit_worker_by_lua (require a global table)
--- http_config eval
    qq{lua_package_path '$::HtmlDir/?.lua;;';
        exit_worker_by_lua_block {
            foo = require("foo")
            ngx.log(ngx.NOTICE, foo.bar)
        }}
--- config
    location /t {
        content_by_lua_block {
            foo = require("foo")
            foo.bar = "hello, world"
            ngx.say("ok")
        }
    }
--- user_files
>>> foo.lua
return {}
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
hello, world



=== TEST 4: ngx.timer is not allow
--- http_config
    exit_worker_by_lua_block {
        local function bar()
            ngx.log(ngx.ERR, "run the timer!")
        end

        local ok, err = ngx.timer.at(0, bar)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer: ", err)
        else
            ngx.log(ngx.NOTICE, "success")
        end
    }
--- config
    location /t {
        echo "ok";
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
API disabled in the context of exit_worker_by_lua*



=== TEST 5: exit_worker_by_lua use shdict
--- http_config
    lua_shared_dict dog 1m;
    exit_worker_by_lua_block {
        local dog = ngx.shared.dog
        local val, err = dog:get("foo")
        if not val then
            ngx.log(ngx.ERR, "failed get shdict: ", err)
        else
            ngx.log(ngx.NOTICE, "get val: ", val)
        end
    }
--- config
    location /t {
        content_by_lua_block {
            local dog = ngx.shared.dog
            dog:set("foo", 100)
            ngx.say("ok")
        }
    }
--- request
GET /t
--- response_body
ok
--- shutdown_error_log
get val: 100



=== TEST 6: skip in cache processes (with exit worker and privileged agent)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    init_by_lua_block {
        assert(require "ngx.process".enable_privileged_agent())
    }

    exit_worker_by_lua_block {
        local process = require "ngx.process"
        ngx.log(ngx.INFO, "hello from exit worker by lua, process type: ", process.type())
    }
--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- no_error_log
[error]
--- shutdown_error_log eval
[
qr/cache loader process \d+ exited/,
qr/cache manager process \d+ exited/,
qr/hello from exit worker by lua, process type: worker/,
qr/hello from exit worker by lua, process type: privileged agent/,
qr/privileged agent process \d+ exited/,
]



=== TEST 7: skipin cache processes (with init worker but without privileged agent)
--- http_config
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    proxy_cache_path /tmp/cache levels=1:2 keys_zone=cache:1m;

    exit_worker_by_lua_block {
        local process = require "ngx.process"
        ngx.log(ngx.INFO, "hello from exit worker by lua, process type: ", process.type())
    }
--- config
    location = /t {
        return 200;
    }
--- request
    GET /t
--- no_error_log
[error]
start privileged agent process
--- shutdown_error_log eval
[
qr/cache loader process \d+ exited/,
qr/cache manager process \d+ exited/,
qr/hello from exit worker by lua, process type: worker/,
]



=== TEST 8: syntax error in exit_worker_by_lua_block
--- http_config
    exit_worker_by_lua_block {
        ngx.log(ngx.debug, "pass")
        error("failed to init"
        ngx.log(ngx.debug, "unreachable")
    }
--- config
    location /t {
        content_by_lua_block {
            ngx.say("hello world")
        }
    }
--- request
    GET /t
--- response_body
hello world
--- shutdown_error_log
exit_worker_by_lua error: exit_worker_by_lua(nginx.conf:25):4: ')' expected (to close '(' at line 3) near 'ngx'



=== TEST 9: syntax error in exit_worker_by_lua_file
--- http_config
    exit_worker_by_lua_file html/exit.lua;
--- config
    location /t {
        content_by_lua_block {
            ngx.say("hello world")
        }
    }
--- user_files
>>> exit.lua
    ngx.log(ngx.debug, "pass")
    error("failed to init"
    ngx.log(ngx.debug, "unreachable")

--- request
    GET /t
--- response_body
hello world
--- shutdown_error_log eval
qr|exit_worker_by_lua_file error: .*?t/servroot\w*/html/exit.lua:3: '\)' expected \(to close '\(' at line 2\) near 'ngx'|
