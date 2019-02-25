# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

no_long_string();

run_tests();

__DATA__

=== TEST 1: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('a 你')";
        echo $res;
    }
--- request
GET /escape
--- response_body
a%20%E4%BD%A0



=== TEST 2: unescape uri in set_by_lua
--- config
    location /unescape {
        set_by_lua $res "return ngx.unescape_uri('a%20%e4%bd%a0')";
        echo $res;
    }
--- request
GET /unescape
--- response_body
a 你



=== TEST 3: escape uri in content_by_lua
--- config
    location /escape {
        content_by_lua "ngx.say(ngx.escape_uri('a 你'))";
    }
--- request
GET /escape
--- response_body
a%20%E4%BD%A0



=== TEST 4: unescape uri in content_by_lua
--- config
    location /unescape {
        content_by_lua "ngx.say(ngx.unescape_uri('a%20%e4%bd%a0'))";
    }
--- request
GET /unescape
--- response_body
a 你



=== TEST 5: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('a+b')";
        echo $res;
    }
--- request
GET /escape
--- response_body
a%2Bb



=== TEST 6: escape uri in set_by_lua
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('\"a/b={}:<>;&[]\\\\^')";
        echo $res;
    }
--- request
GET /escape
--- response_body
%22a%2Fb%3D%7B%7D%3A%3C%3E%3B%26%5B%5D%5C%5E



=== TEST 7: escape uri in set_by_lua
--- config
    location /escape {
        echo hello;
        header_filter_by_lua '
            ngx.header.baz = ngx.escape_uri(" ")
        ';
    }
--- request
GET /escape
--- response_headers
baz: %20
--- response_body
hello



=== TEST 8: escape a string that cannot be escaped
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('abc')";
        echo $res;
    }
--- request
GET /escape
--- response_body
abc



=== TEST 9: escape an empty string that cannot be escaped
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri('')";
        echo $res;
    }
--- request
GET /escape
--- response_body eval: "\n"



=== TEST 10: escape nil
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri(nil)";
        echo "[$res]";
    }
--- request
GET /escape
--- response_body
[]



=== TEST 11: escape numbers
--- config
    location /escape {
        set_by_lua $res "return ngx.escape_uri(32)";
        echo "[$res]";
    }
--- request
GET /escape
--- response_body
[32]



=== TEST 12: unescape nil
--- config
    location = /t {
        set_by_lua $res "return ngx.unescape_uri(nil)";
        echo "[$res]";
    }
--- request
GET /t
--- response_body
[]



=== TEST 13: unescape numbers
--- config
    location = /t {
        set_by_lua $res "return ngx.unescape_uri(32)";
        echo "[$res]";
    }
--- request
GET /t
--- response_body
[32]



=== TEST 14: reserved chars
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("-_.!~*'()"))
            ngx.say(ngx.escape_uri(",$@|`"))
        }
    }
--- request
GET /lua
--- response_body
-_.!~*'()
%2C%24%40%7C%60
--- no_error_log
[error]
