# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 4);

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



=== TEST 15: escape type argument
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("https://www.google.com", 0))
            ngx.say(ngx.escape_uri("https://www.google.com/query?q=test", 0))
            ngx.say(ngx.escape_uri("https://www.google.com/query?\r\nq=test", 0))
            ngx.say(ngx.escape_uri("-_.~!*'();:@&=+$,/?#", 0))
            ngx.say(ngx.escape_uri("<>[]{}\\\" ", 0))
        }
    }
--- request
GET /lua
--- response_body
https://www.google.com
https://www.google.com/query%3Fq=test
https://www.google.com/query%3F%0D%0Aq=test
-_.~!*'();:@&=+$,/%3F%23
<>[]{}\"%20
--- no_error_log
[error]



=== TEST 16: escape type argument
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 0))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 1))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 2))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 3))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 4))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 5))
            ngx.say(ngx.escape_uri("https://www.google.com/?t=abc@ :", 6))
        }
    }
--- request
GET /lua
--- response_body
https://www.google.com/%3Ft=abc@%20:
https://www.google.com/%3Ft=abc@%20:
https%3A%2F%2Fwww.google.com%2F%3Ft%3Dabc%40%20%3A
https://www.google.com/?t=abc@%20:
https://www.google.com/?t=abc@%20:
https://www.google.com/?t=abc@%20:
https://www.google.com/?t=abc@%20:
--- no_error_log
[error]



=== TEST 17: escape type out of range
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("https://www.google.com", -1))
        }
    }
--- request
GET /lua
--- error_code: 500
--- error_log eval
qr/\[error\] \d+#\d+: \*\d+ lua entry thread aborted: runtime error: "type" \-1 out of range/



=== TEST 18: escape type out of range
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("https://www.google.com", 10))
        }
    }
--- request
GET /lua
--- error_code: 500
--- error_log eval
qr/\[error\] \d+#\d+: \*\d+ lua entry thread aborted: runtime error: "type" 10 out of range/



=== TEST 19: escape type not integer
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.escape_uri("https://www.google.com", true))
        }
    }
--- request
GET /lua
--- error_code: 500
--- error_log eval
qr/\[error\] \d+#\d+: \*\d+ lua entry thread aborted: runtime error: "type" is not a number/



=== TEST 20: invalid unescape sequences
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.unescape_uri("%ua%%20%au"))
        }
    }
--- request
GET /lua
--- response_body
%ua% %au



=== TEST 21: invalid unescape sequences where remain length less than 2
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(ngx.unescape_uri("%a")) -- first character is good
            ngx.say(ngx.unescape_uri("%u")) -- first character is bad
            ngx.say(ngx.unescape_uri("%"))
            ngx.say(ngx.unescape_uri("good%20job%"))
        }
    }
--- request
GET /lua
--- response_body
%a
%u
%
good job%
