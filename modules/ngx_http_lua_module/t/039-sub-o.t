# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 6);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: matched but w/o variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "howdy", "o")
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
            local s, n = ngx.re.sub("hello, world", "[A-Z]+", "howdy", "o")
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
            local s, n = ngx.re.sub("a b c d", "(b) (c)", "[$0] [$1] [$2] [$3] [$134]", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1



=== TEST 4: matched and with named variables (bad template)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("a b c d",
                                         "(b) (c)",
                                         "[$0] [$1] [$2] [$3] [$hello]",
                                         "o")
            if s then
                ngx.say(s, ": ", n)

            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
attempt to use named capturing variable "hello" (named captures not supported yet)



=== TEST 5: matched and with named variables (bracketed)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("a b c d",
                                         "(b) (c)",
                                         "[$0] [$1] [$2] [$3] [${hello}]",
                                         "o")
            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
attempt to use named capturing variable "hello" (named captures not supported yet)



=== TEST 6: matched and with bracketed variables
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134}]", "o")
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
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134]", "o")
            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
the closing bracket in "134" variable is missing



=== TEST 8: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134", "o")
            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
the closing bracket in "134" variable is missing



=== TEST 9: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${", "o")
            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
lua script: invalid capturing variable name found in "[$0] [$1] [${2}] [$3] [${"



=== TEST 10: trailing $
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [$", "o")
            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile the replacement template
--- error_log
lua script: invalid capturing variable name found in "[$0] [$1] [${2}] [$3] [$"



=== TEST 11: matched but w/o variables and with literal $
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "ho$$wdy", "o")
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
            local s, n = ngx.re.sub("hello, 1234", " [0-9] ", "x", "xo")
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
            local s, n = ngx.re.sub("hello, 1234", "[0-9]", "x", "ao")
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

            local s, n = ngx.re.sub("hello, 34", "([0-9])", repl, "o")
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

            local s, n = ngx.re.sub("hello, 34", "([A-Z])", repl, "o")
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
--- SKIP
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([A-Z])", true, "o")
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
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([0-9])", 72, "o")
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
--- SKIP
--- config
    location /re {
        content_by_lua '
            local f = function (m) end
            local rc, s, n = pcall(ngx.re.sub, "hello, 34", "([0-9])", f, "o")
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
            local s, n = ngx.re.sub("hello, world", "[a-z]+", "howdy", "o")
            return s
        ';
        echo $res;
    }
--- request
    GET /re
--- response_body
howdy, world



=== TEST 20: with regex cache (with text replace)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "([A-Z]+)", "baz", "io")
            ngx.say(s)
            ngx.say(n)

            local s, n = ngx.re.sub("howdy, 1234", "([A-Z]+)", "baz", "io")
            ngx.say(s)
            ngx.say(n)


            s, n = ngx.re.sub("1234, okay", "([A-Z]+)", "blah", "io")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("hi, 1234", "([A-Z]+)", "hello", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
baz, 1234
1
baz, 1234
1
1234, blah
1
hi, 1234
0



=== TEST 21: with regex cache (with func replace)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "([A-Z]+)", "baz", "io")
            ngx.say(s)
            ngx.say(n)

            local s, n = ngx.re.sub("howdy, 1234", "([A-Z]+)", function () return "bah" end, "io")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("1234, okay", "([A-Z]+)", function () return "blah" end, "io")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("hi, 1234", "([A-Z]+)", "hello", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
baz, 1234
1
bah, 1234
1
1234, blah
1
hi, 1234
0



=== TEST 22: exceeding regex cache max entries
--- http_config
    lua_regex_cache_max_entries 2;
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "([0-9]+)", "hello", "o")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("howdy, 567", "([0-9]+)", "hello", "oi")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("hiya, 98", "([0-9]+)", "hello", "ox")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, hello
1
howdy, hello
1
hiya, hello
1



=== TEST 23: disable regex cache completely
--- http_config
    lua_regex_cache_max_entries 0;
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "([0-9]+)", "hello", "o")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("howdy, 567", "([0-9]+)", "hello", "oi")
            ngx.say(s)
            ngx.say(n)

            s, n = ngx.re.sub("hiya, 98", "([0-9]+)", "hello", "ox")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, hello
1
howdy, hello
1
hiya, hello
1



=== TEST 24: empty replace
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234", "([0-9]+)", "", "o")
            ngx.say(s)
            ngx.say(n)

            local s, n = ngx.re.sub("hi, 5432", "([0-9]+)", "", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, 
1
hi, 
1



=== TEST 25: matched and with variables w/o using named patterns in sub
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", "(?<first>b) (?<second>c)", "[$0] [$1] [$2] [$3] [$134]", "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1



=== TEST 26: matched and with variables using named patterns in func
--- config
    error_log /tmp/nginx_error debug;
    location /re {
        content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "] [" .. m["first"] .. "] [" .. m[2] .. "]"
            end

            local s, n = ngx.re.sub("a b c d", "(?<first>b) (?<second>c)", repl, "o")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] d
1
