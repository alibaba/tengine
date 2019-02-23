# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

#no_diff();
#no_long_string();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: sanity (inline)
--- http_config
    init_by_lua 'foo = "hello, FOO"';
--- config
    location /lua {
        content_by_lua 'ngx.say(foo)';
    }
--- request
GET /lua
--- response_body
hello, FOO
--- no_error_log
[error]



=== TEST 2: sanity (file)
--- http_config
    init_by_lua_file html/init.lua;
--- config
    location /lua {
        content_by_lua 'ngx.say(foo)';
    }
--- user_files
>>> init.lua
foo = "hello, FOO"
--- request
GET /lua
--- response_body
hello, FOO
--- no_error_log
[error]



=== TEST 3: require
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
    init_by_lua 'require "blah"';
--- config
    location /lua {
        content_by_lua '
            blah.go()
        ';
    }
--- user_files
>>> blah.lua
module(..., package.seeall)

function go()
    ngx.say("hello, blah")
end
--- request
GET /lua
--- response_body
hello, blah
--- no_error_log
[error]



=== TEST 4: shdict (single)
--- http_config
    lua_shared_dict dogs 1m;
    init_by_lua '
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 6)
        dogs:get("Jim")
    ';
--- config
    location /lua {
        content_by_lua '
            local dogs = ngx.shared.dogs
            ngx.say("Jim: ", dogs:get("Jim"))
        ';
    }
--- request
GET /lua
--- response_body
Jim: 6
--- no_error_log
[error]



=== TEST 5: shdict (multi)
--- http_config
    lua_shared_dict dogs 1m;
    lua_shared_dict cats 1m;
    init_by_lua '
        local dogs = ngx.shared.dogs
        dogs:set("Jim", 6)
        dogs:get("Jim")
        local cats = ngx.shared.cats
        cats:set("Tom", 2)
        dogs:get("Tom")
    ';
--- config
    location /lua {
        content_by_lua '
            local dogs = ngx.shared.dogs
            ngx.say("Jim: ", dogs:get("Jim"))
        ';
    }
--- request
GET /lua
--- response_body
Jim: 6
--- no_error_log
[error]



=== TEST 6: print
--- http_config
    lua_shared_dict dogs 1m;
    lua_shared_dict cats 1m;
    init_by_lua '
        print("log from init_by_lua")
    ';
--- config
    location /lua {
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- grep_error_log chop
log from init_by_lua
--- grep_error_log_out eval
["log from init_by_lua\n", ""]



=== TEST 7: ngx.log
--- http_config
    lua_shared_dict dogs 1m;
    lua_shared_dict cats 1m;
    init_by_lua '
        ngx.log(ngx.NOTICE, "log from init_by_lua")
    ';
--- config
    location /lua {
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- grep_error_log chop
log from init_by_lua
--- grep_error_log_out eval
["log from init_by_lua\n", ""]



=== TEST 8: require (with shm defined)
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
    lua_shared_dict dogs 1m;
    init_by_lua 'require "blah"';
--- config
    location /lua {
        content_by_lua '
            blah.go()
        ';
    }
--- user_files
>>> blah.lua
module(..., package.seeall)

function go()
    ngx.say("hello, blah")
end
--- request
GET /lua
--- response_body
hello, blah
--- no_error_log
[error]



=== TEST 9: coroutine API (inlined init_by_lua)
--- http_config
    init_by_lua '
        local function f()
            foo = 32
            coroutine.yield(78)
            bar = coroutine.status(coroutine.running())
        end
        local co = coroutine.create(f)
        local ok, err = coroutine.resume(co)
        if not ok then
            print("Failed to resume our co: ", err)
            return
        end
        baz = err
        coroutine.resume(co)
    ';
--- config
    location /lua {
        content_by_lua '
            ngx.say("foo = ", foo)
            ngx.say("bar = ", bar)
            ngx.say("baz = ", baz)
        ';
    }
--- request
GET /lua
--- response_body
foo = 32
bar = running
baz = 78
--- no_error_log
[error]
Failed to resume our co: 



=== TEST 10: coroutine API (init_by_lua_file)
--- http_config
    init_by_lua_file html/init.lua;

--- config
    location /lua {
        content_by_lua '
            ngx.say("foo = ", foo)
            ngx.say("bar = ", bar)
            ngx.say("baz = ", baz)
        ';
    }
--- request
GET /lua
--- user_files
>>> init.lua
local function f()
    foo = 32
    coroutine.yield(78)
    bar = coroutine.status(coroutine.running())
end
local co = coroutine.create(f)
local ok, err = coroutine.resume(co)
if not ok then
    print("Failed to resume our co: ", err)
    return
end
baz = err
coroutine.resume(co)

--- response_body
foo = 32
bar = running
baz = 78
--- no_error_log
[error]
Failed to resume our co: 



=== TEST 11: access a field in the ngx. table
--- http_config
    init_by_lua '
        print("INIT 1: foo = ", ngx.foo)
        ngx.foo = 3
        print("INIT 2: foo = ", ngx.foo)
    ';
--- config
    location /t {
        echo ok;
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- grep_error_log eval: qr/INIT \d+: foo = \S+/
--- grep_error_log_out eval
[
"INIT 1: foo = nil
INIT 2: foo = 3
",
"",
]



=== TEST 12: error in init
--- http_config
    init_by_lua_block {
        error("failed to init")
    }
--- config
    location /t {
        echo ok;
    }
--- must_die
--- error_log
failed to init
--- error_log
[error]
