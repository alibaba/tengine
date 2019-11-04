# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("[hello, world]", "[a-z]+", "howdy", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[howdy, howdy]
2



=== TEST 2: trimmed
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("hello, world", "[a-z]+", "howdy", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
howdy, howdy
2



=== TEST 3: not matched
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("hello, world", "[A-Z]+", "howdy", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, world
0



=== TEST 4: replace by function (trimmed)
--- config
    location /re {
        content_by_lua '
            local f = function (m)
                return "[" .. m[0] .. "," .. m[1] .. "]"
            end

            local s, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", f, "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[hello,h], [world,w]
2



=== TEST 5: replace by function (not trimmed)
--- config
    location /re {
        content_by_lua '
            local f = function (m)
                return "[" .. m[0] .. "," .. m[1] .. "]"
            end

            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", f, "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
{[hello,h], [world,w]}
2



=== TEST 6: replace by script (trimmed)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", "[$0,$1]", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[hello,h], [world,w]
2



=== TEST 7: replace by script (not trimmed)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", "[$0,$1]", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
{[hello,h], [world,w]}
2



=== TEST 8: set_by_lua
--- config
    location /re {
        set_by_lua $res '
            local f = function (m)
                return "[" .. m[0] .. "," .. m[1] .. "]"
            end

            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", f, "o")
            return s
        ';
        echo $res;
    }
--- request
    GET /re
--- response_body
{[hello,h], [world,w]}



=== TEST 9: look-behind assertion
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "h$0", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
{foohbarhbaz}
2



=== TEST 10: named pattern repl w/ callback
--- config
    location /re {
       content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "," .. m["first"] .. "]"
            end

            local s, n = ngx.re.gsub("hello, world", "(?<first>[a-z])[a-z]+", repl, "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[hello,h], [world,w]
2
