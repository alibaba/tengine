# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: $prefix
--- http_config: lua_package_path "$prefix/html/?.lua;;";
--- config
    location /t {
        content_by_lua '
            local foo = require "foo"
            foo.go()
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

function go()
    ngx.say("Greetings from module foo.")
end
--- request
GET /t
--- response_body
Greetings from module foo.
--- no_error_log
[error]



=== TEST 2: ${prefix}
--- http_config: lua_package_path "${prefix}html/?.lua;;";
--- config
    location /t {
        content_by_lua '
            local foo = require "foo"
            foo.go()
        ';
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

function go()
    ngx.say("Greetings from module foo.")
end
--- request
GET /t
--- response_body
Greetings from module foo.
--- no_error_log
[error]
