# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

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

=== TEST 1: matched but w/o variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "howdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
howdy, world
1



=== TEST 2: not matched
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[A-Z]+", "howdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, world
0



=== TEST 3: matched and with variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", "(b) (c)", "[$0] [$1] [$2] [$3] [$134]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1



=== TEST 4: matched and with named variables
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [$hello]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [$2] [$3] [$hello]"
nil



=== TEST 5: matched and with named variables (bracketed)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [${hello}]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [$2] [$3] [${hello}]"
nil



=== TEST 6: matched and with bracketed variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134}]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[b c] [b] [c] [] [] d
1



=== TEST 7: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134]")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${134]"
nil



=== TEST 8: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${134"
nil



=== TEST 9: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [${"
nil



=== TEST 10: trailing $
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [$")
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad template for substitution: "[$0] [$1] [${2}] [$3] [$"
nil



=== TEST 11: matched but w/o variables and with literal $
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "ho$$wdy")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
ho$wdy, world
1



=== TEST 12: non-anchored match
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "[0-9]", "x")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, x234
1



=== TEST 13: anchored match
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "[0-9]", "x", "a")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
0



=== TEST 14: function replace
--- config
    location /re {
        content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "] [" .. m[1] .. "]"
            end

            local s, n = ngx.re.sub("hello, 34", "([0-9])", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, [3] [3]4
1



=== TEST 15: function replace (failed)
--- config
    location /re {
        content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "] [" .. m[1] .. "]"
            end

            local s, n = ngx.re.sub("hello, 34", "([A-Z])", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, 34
0



=== TEST 16: bad repl arg type
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([A-Z])", true)
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad argument #3 to '?' (string, number, or function expected, got boolean)
nil



=== TEST 17: use number to replace
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([0-9])", 72)
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
true
hello, 724
1



=== TEST 18: bad function return value type
--- config
    location /re {
        content_by_lua '
            local f = function (m) end
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([0-9])", f)
            ngx.say(rc)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
false
bad argument #3 to '?' (string or number expected to be returned by the replace function, got nil)
nil



=== TEST 19: matched but w/o variables (set_by_lua)
--- config
    location /re {
        set_by_lua $res '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "howdy")
            return s
        ';
        echo $res;
    }
--- request
    GET /re
--- response_body
howdy, world

