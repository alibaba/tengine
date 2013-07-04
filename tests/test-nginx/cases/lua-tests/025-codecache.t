# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

our $HtmlDir = html_dir;

run_tests();

__DATA__

=== TEST 1: code cache on by default
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32



=== TEST 2: code cache explicitly on
--- config
    location /lua {
        lua_code_cache on;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32



=== TEST 3: code cache explicitly off
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
101



=== TEST 4: code cache explicitly off (server level)
--- config
    lua_code_cache off;

    location /lua {
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
101



=== TEST 5: code cache explicitly off (server level) but be overridden in the location
--- config
    lua_code_cache off;

    location /lua {
        lua_code_cache on;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("ngx.say(101)")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(32)
--- request
GET /main
--- response_body
32
updated
32



=== TEST 6: code cache explicitly off (affects require) + content_by_lua
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua '
            local foo = require "foo";
        ';
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); ngx.say(102);")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> foo.lua
module(..., package.seeall); ngx.say(32);
--- request
GET /main
--- response_body
32
updated
102



=== TEST 7: code cache explicitly off (affects require) + content_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); ngx.say(102);")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
local foo = require "foo";
>>> foo.lua
module(..., package.seeall); ngx.say(32);
--- request
GET /main
--- response_body
32
updated
102



=== TEST 8: code cache explicitly off (affects require) + set_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache off;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); return 102;")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return require "foo"
>>> foo.lua
module(..., package.seeall); return 32;
--- request
GET /main
--- response_body
32
updated
102



=== TEST 9: code cache explicitly on (affects require) + set_by_lua_file
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /lua {
        lua_code_cache on;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/foo.lua", "w"))
            f:write("module(..., package.seeall); return 102;")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return require "foo"
>>> foo.lua
module(..., package.seeall); return 32;
--- request
GET /main
--- response_body
32
updated
32



=== TEST 10: code cache explicitly off + set_by_lua_file
--- config
    location /lua {
        lua_code_cache off;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("return 101")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return 32
--- request
GET /main
--- response_body
32
updated
101



=== TEST 11: code cache explicitly on + set_by_lua_file
--- config
    location /lua {
        lua_code_cache on;
        set_by_lua_file $a html/test.lua;
        echo $a;
    }
    location /update {
        content_by_lua '
            -- os.execute("(echo HERE; pwd) > /dev/stderr")
            local f = assert(io.open("t/servroot/html/test.lua", "w"))
            f:write("return 101")
            f:close()
            ngx.say("updated")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /update;
        echo_location /lua;
    }
--- user_files
>>> test.lua
return 32
--- request
GET /main
--- response_body
32
updated
32



=== TEST 12: no clear builtin lib "string"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua_file html/test.lua;
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- user_files
>>> test.lua
ngx.say(string.len("hello"))
ngx.say(table.concat({1,2,3}, ", "))
--- request
    GET /main
--- response_body
5
1, 2, 3
5
1, 2, 3



=== TEST 13: no clear builtin lib "string"
--- config
    location /lua {
        lua_code_cache off;
        content_by_lua '
            ngx.say(string.len("hello"))
            ngx.say(table.concat({1,2,3}, ", "))
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- request
    GET /main
--- response_body
5
1, 2, 3
5
1, 2, 3



=== TEST 14: no clear builtin lib "string"
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    lua_code_cache off;
    location /lua {
        content_by_lua '
            local test = require("test")
        ';
    }
    location /main {
        echo_location /lua;
        echo_location /lua;
    }
--- request
    GET /main
--- user_files
>>> test.lua
module("test", package.seeall)

string = require("string")
math = require("math")
io = require("io")
os = require("os")
table = require("table")
coroutine = require("coroutine")
package = require("package")
ngx.say("OK")
--- response_body
OK
OK



=== TEST 15: skip luarocks
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';
     lua_code_cache off;"
--- config
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.luarocks = nil;
            local foo = require "luarocks";
            foo.hi()
        ';
    }

    location /check {
        content_by_lua '
            local foo = package.loaded.luarocks
            if foo then
                ngx.say("found")
            else
                ngx.say("not found")
            end
        ';
    }
--- request
GET /main
--- user_files
>>> luarocks.lua
module(..., package.seeall);

ngx.say("loading");

function hi ()
    ngx.say("hello, foo")
end;
--- response_body
loading
hello, foo
found
found



=== TEST 16: skip luarocks*
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';
     lua_code_cache off;"
--- config
    location /main {
        echo_location /load;
        echo_location /check;
        echo_location /check;
    }

    location /load {
        content_by_lua '
            package.loaded.luarocks2 = nil;
            local foo = require "luarocks2";
            foo.hi()
        ';
    }

    location /check {
        content_by_lua '
            local foo = package.loaded.luarocks2
            if foo then
                ngx.say("found")
            else
                ngx.say("not found")
            end
        ';
    }
--- request
GET /main
--- user_files
>>> luarocks2.lua
module(..., package.seeall);

ngx.say("loading");

function hi ()
    ngx.say("hello, foo")
end;
--- response_body
loading
hello, foo
found
found



=== TEST 17: clear _G table
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    lua_code_cache off;
    location /t {
        content_by_lua '
            if not _G.foo then
                _G.foo = 1
            else
                _G.foo = _G.foo + 1
            end
            ngx.say("_G.foo: ", _G.foo)
        ';
    }
--- request
    GET /t
--- response_body
_G.foo: 1

