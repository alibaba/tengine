# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

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
--- error_log
log from init_by_lua



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
--- error_log
log from init_by_lua



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

