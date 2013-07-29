# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 9);

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
            local s, n, err = ngx.re.sub("a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [$hello]")
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
error: bad template for substitution: "[$0] [$1] [$2] [$3] [$hello]"
--- error_log
attempt to use named capturing variable "hello" (named captures not supported yet)



=== TEST 5: matched and with named variables (bracketed)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("a b c d",
                "(b) (c)", "[$0] [$1] [$2] [$3] [${hello}]")
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
error: bad template for substitution: "[$0] [$1] [$2] [$3] [${hello}]"
--- error_log
attempt to use named capturing variable "hello" (named captures not supported yet)



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
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134]")
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
error: bad template for substitution: "[$0] [$1] [${2}] [$3] [${134]"
--- error_log
the closing bracket in "134" variable is missing



=== TEST 8: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${134")
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
error: bad template for substitution: "[$0] [$1] [${2}] [$3] [${134"
--- error_log
the closing bracket in "134" variable is missing



=== TEST 9: matched and with bracketed variables (unmatched brackets)
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [${")
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
error: bad template for substitution: "[$0] [$1] [${2}] [$3] [${"
--- error_log
lua script: invalid capturing variable name found in "[$0] [$1] [${2}] [$3] [${"



=== TEST 10: trailing $
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("b c d", "(b) (c)", "[$0] [$1] [${2}] [$3] [$")
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
error: bad template for substitution: "[$0] [$1] [${2}] [$3] [$"
--- error_log
lua script: invalid capturing variable name found in "[$0] [$1] [${2}] [$3] [$"



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



=== TEST 20: matched and with variables w/o using named patterns in sub
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", "(?<first>b) (?<second>c)", "[$0] [$1] [$2] [$3] [$134]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1



=== TEST 21: matched and with variables using named patterns in func
--- config
    error_log /tmp/nginx_error debug;
    location /re {
        content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "] [" .. m["first"] .. "] [" .. m[2] .. "]"
            end

            local s, n = ngx.re.sub("a b c d", "(?<first>b) (?<second>c)", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] d
1



=== TEST 22: matched and with variables w/ using named patterns in sub
This is still a TODO
--- SKIP
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", "(?<first>b) (?<second>c)", "[$0] [${first}] [${second}] [$3] [$134]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
a [b c] [b] [c] [] [] d
1
--- no_error_log
[error]



=== TEST 23: $0 without parens
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("a b c d", [[\w]], "[$0]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[a] b c d
1
--- no_error_log
[error]



=== TEST 24: bad pattern
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("hello\\nworld", "(abc", "")
            if s then
                ngx.say("subs: ", n)

            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]



=== TEST 25: bad UTF-8
--- config
    location = /t {
        content_by_lua '
            local target = "你好"
            local regex = "你好"

            -- Note the D here
            local s, n, err = ngx.re.sub(string.sub(target, 1, 4), regex, "", "u")

            if s then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", err)
            end
        ';
    }
--- request
GET /t
--- response_body_like chop
error: pcre_exec\(\) failed: -10 on "你.*?" using "你好"

--- no_error_log
[error]

