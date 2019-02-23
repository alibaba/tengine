# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 19);

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
error: failed to compile the replacement template
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
error: failed to compile the replacement template
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
error: failed to compile the replacement template
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
error: failed to compile the replacement template
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
error: failed to compile the replacement template
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
error: failed to compile the replacement template
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
--- SKIP



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
--- SKIP
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
--- no_error_log
[error]
[alert]
--- timeout: 5



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
error: pcre_compile() failed: missing ) in "(abc"
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
error: pcre_exec\(\) failed: -10

--- no_error_log
[error]



=== TEST 26: UTF-8 mode without UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("你好", ".", "a", "U")
            if s then
                ngx.say("s: ", s)
            end
        ';
    }
--- stap
probe process("$LIBPCRE_PATH").function("pcre_compile") {
    printf("compile opts: %x\n", $options)
}

probe process("$LIBPCRE_PATH").function("pcre_exec") {
    printf("exec opts: %x\n", $options)
}

--- stap_out
compile opts: 800
exec opts: 2000

--- request
    GET /re
--- response_body
s: a好
--- no_error_log
[error]



=== TEST 27: UTF-8 mode with UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("你好", ".", "a", "u")
            if s then
                ngx.say("s: ", s)
            end
        ';
    }
--- stap
probe process("$LIBPCRE_PATH").function("pcre_compile") {
    printf("compile opts: %x\n", $options)
}

probe process("$LIBPCRE_PATH").function("pcre_exec") {
    printf("exec opts: %x\n", $options)
}

--- stap_out
compile opts: 800
exec opts: 0

--- request
    GET /re
--- response_body
s: a好
--- no_error_log
[error]



=== TEST 28: just hit match limit
--- http_config
    lua_regex_match_limit 5000;
--- config
    location /re {
        content_by_lua_file html/a.lua;
    }

--- user_files
>>> a.lua
local re = [==[(?i:([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:=|<=>|r?like|sounds\s+like|regexp)([\s'\"`´’‘\(\)]*)?\2|([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:!=|<=|>=|<>|<|>|\^|is\s+not|not\s+like|not\s+regexp)([\s'\"`´’‘\(\)]*)?(?!\6)([\d\w]+))]==]

local s = string.rep([[ABCDEFG]], 10)

local start = ngx.now()

local res, cnt, err = ngx.re.sub(s, re, "", "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if err then
    ngx.say("error: ", err)
    return
end
ngx.say("sub: ", cnt)

--- request
    GET /re
--- response_body
error: pcre_exec() failed: -8



=== TEST 29: just not hit match limit
--- http_config
    lua_regex_match_limit 5100;
--- config
    location /re {
        content_by_lua_file html/a.lua;
    }

--- user_files
>>> a.lua
local re = [==[(?i:([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:=|<=>|r?like|sounds\s+like|regexp)([\s'\"`´’‘\(\)]*)?\2|([\s'\"`´’‘\(\)]*)?([\d\w]+)([\s'\"`´’‘\(\)]*)?(?:!=|<=|>=|<>|<|>|\^|is\s+not|not\s+like|not\s+regexp)([\s'\"`´’‘\(\)]*)?(?!\6)([\d\w]+))]==]

local s = string.rep([[ABCDEFG]], 10)

local start = ngx.now()

local res, cnt, err = ngx.re.sub(s, re, "", "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if err then
    ngx.say("error: ", err)
    return
end
ngx.say("sub: ", cnt)

--- request
    GET /re
--- response_body
sub: 0



=== TEST 30: bug: sub incorrectly swallowed a character is the first character
Original bad result: estCase
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("TestCase", "^ *", "", "o")
            if s then
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
TestCase



=== TEST 31: bug: sub incorrectly swallowed a character is not the first character
Original bad result: .b.d
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("abcd", "(?=c)", ".")
            if s then
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
ab.cd



=== TEST 32: ngx.re.gsub: recursive calling (github #445)
--- config

location = /t {
    content_by_lua '
        local function test()
            local data = [[
                OUTER {FIRST}
]]

            local p1 = "(OUTER)(.+)"
            local p2 = "{([A-Z]+)}"

            ngx.print(data)

            local res =  ngx.re.gsub(data, p1, function(m)
                -- ngx.say("pre: m[1]: [", m[1], "]")
                -- ngx.say("pre: m[2]: [", m[2], "]")

                local res = ngx.re.gsub(m[2], p2, function(_)
                    return "REPLACED"
                end, "")

                -- ngx.say("post: m[1]: [", m[1], "]")
                -- ngx.say("post m[2]: [", m[2], "]")
                return m[1] .. res
            end, "")

            ngx.print(res)
        end

        test()
    ';
}
--- request
GET /t
--- response_body
                OUTER {FIRST}
                OUTER REPLACED
--- no_error_log
[error]
bad argument type
NYI



=== TEST 33: function replace (false for groups)
--- config
    location /re {
        content_by_lua '
            local repl = function (m)
                print("group 1: ", m[2])
                return "[" .. m[0] .. "] [" .. m[1] .. "]"
            end

            local s, n = ngx.re.sub("hello, 34", "([0-9])|(world)", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
hello, [3] [3]4
1
--- error_log
group 1: false
