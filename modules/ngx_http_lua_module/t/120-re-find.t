# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 1);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "jo")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 11
matched: 1234
--- no_error_log
[error]



=== TEST 2: empty matched string
--- config
    location /re {
        content_by_lua '
            local s = "hello, world"
            local from, to, err = ngx.re.find(s, "[0-9]*")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 0
matched: 
--- no_error_log
[error]



=== TEST 3: multiple captures (with o)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([a-z]+).*?([0-9]{2})[0-9]+", "o")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello, 1234
--- no_error_log
[error]



=== TEST 4: not matched
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "foo")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 5: case sensitive by default
--- config
    location /re {
        content_by_lua '
            local from = ngx.re.find("hello, 1234", "HELLO")
            if from then
                ngx.say(from)
            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 6: case insensitive
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "HELLO", "i")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 5
matched: hello
--- no_error_log
[error]



=== TEST 7: UTF-8 mode
--- config
    location /re {
        content_by_lua '
            local s = "hello章亦春"
            local from, to, err = ngx.re.find(s, "HELLO.{2}", "iu")
            if not from then
                ngx.say("FAIL: ", err)
                return
            end

            ngx.say(string.sub(s, from, to))
        ';
    }
--- request
    GET /re
--- response_body_like chop
^(?:FAIL: bad argument \#2 to '\?' \(pcre_compile\(\) failed: this version of PCRE is not compiled with PCRE_UTF8 support in "HELLO\.\{2\}" at "HELLO\.\{2\}"\)|hello章亦)$
--- no_error_log
[error]



=== TEST 8: multi-line mode (^ at line head)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "^world", "m")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 7
to: 11
matched: world
--- no_error_log
[error]



=== TEST 9: multi-line mode (. does not match \n)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "m")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 5
matched: hello
--- no_error_log
[error]



=== TEST 10: single-line mode (^ as normal)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "^world", "s")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 11: single-line mode (dot all)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "s")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello
world
--- no_error_log
[error]



=== TEST 12: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "\\\\w     \\\\w", "x")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 2
matched: he
--- no_error_log
[error]



=== TEST 13: bad pattern
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, "(abc")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)

                else
                    ngx.say("not matched.")
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
error: pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]



=== TEST 14: bad option
--- config
    location /re {
        content_by_lua '
            local s = "hello\\nworld"
            local from, to, err = ngx.re.find(s, ".*", "H")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
unknown flag "H"



=== TEST 15: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "a")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched.
--- no_error_log
[error]



=== TEST 16: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            local s = "1234, hello"
            local from, to, err = ngx.re.find(s, "([0-9]+)", "a")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 4
matched: 1234
--- no_error_log
[error]



=== TEST 17: match with ctx but no pos
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local from, to = ngx.re.find("1234, hello", "([0-9]+)", "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 18: match with ctx and a pos
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 3 }
            local from, to, err = ngx.re.find("1234, hello", "([0-9]+)", "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 3
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 19: named subpatterns w/ extraction
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "(?<first>[a-z]+), [0-9]+")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                if err then
                    ngx.say("error: ", err)
                    return
                end

                ngx.say("not matched.")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 1
to: 11
matched: hello, 1234
--- no_error_log
[error]



=== TEST 20: bad UTF-8
--- config
    location = /t {
        content_by_lua '
            local target = "你好"
            local regex = "你好"

            local from, to, err = ngx.re.find(string.sub(target, 1, 4), regex, "u")

            if err then
                ngx.say("error: ", err)
                return
            end

            if m then
                ngx.say("matched: ", from)
            else
                ngx.say("not matched")
            end
        ';
    }
--- request
GET /t
--- response_body_like chop
^error: pcre_exec\(\) failed: -10$

--- no_error_log
[error]



=== TEST 21: UTF-8 mode without UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local s = "你好"
            local from, to, err = ngx.re.find(s, ".", "U")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))

            else
                ngx.say("not matched.")
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
from: 1
to: 3
matched: 你
--- no_error_log
[error]



=== TEST 22: just hit match limit
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

local from, to, err = ngx.re.find(s, re, "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if not from then
    if err then
        ngx.say("error: ", err)
        return
    end
    ngx.say("failed to match.")
    return
end

--- request
    GET /re
--- response_body
error: pcre_exec() failed: -8
--- no_error_log
[error]



=== TEST 23: just not hit match limit
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

local from, to, err = ngx.re.find(s, re, "o")

--[[
ngx.update_time()
local elapsed = ngx.now() - start
ngx.say(elapsed, " sec elapsed.")
]]

if not from then
    if err then
        ngx.say("error: ", err)
        return
    end
    ngx.say("failed to match")
    return
end

--- request
    GET /re
--- response_body
failed to match
--- no_error_log
[error]



=== TEST 24: specify the group (1)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 1)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 8
matched: 1
--- no_error_log
[error]



=== TEST 25: specify the group (0)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 0)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 8
to: 11
matched: 1234
--- no_error_log
[error]



=== TEST 26: specify the group (2)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 2)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 9
to: 11
matched: 234
--- no_error_log
[error]



=== TEST 27: specify the group (3)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 3)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
error: nth out of bound
--- no_error_log
[error]



=== TEST 28: specify the group (4)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])([0-9]+)", "jo", nil, 4)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
error: nth out of bound
--- no_error_log
[error]



=== TEST 29: nil submatch (2nd)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "([0-9])|(hello world)", "jo", nil, 2)
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched!
--- no_error_log
[error]



=== TEST 30: nil submatch (1st)
--- config
    location /re {
        content_by_lua '
            local s = "hello, 1234"
            local from, to, err = ngx.re.find(s, "(hello world)|([0-9])", "jo", nil, 1)
            if from or to then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched!
--- no_error_log
[error]



=== TEST 31: match with ctx and a pos (anchored by \G)
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 3 }
            local from, to, err = ngx.re.find("1234, hello", [[(\G[0-9]+)]], "", ctx)
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("pos: ", ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say("pos: ", ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
from: 3
to: 4
pos: 5
--- no_error_log
[error]



=== TEST 32: ignore match limit in DFA mode
--- http_config
    lua_regex_match_limit 1;
--- config
    location /re {
        content_by_lua_block {
            local s = "This is <something> <something else> <something further> no more"
            local from, to, err = ngx.re.find(s, "<.*>", "d")
            if from then
                ngx.say("from: ", from)
                ngx.say("to: ", to)
                ngx.say("matched: ", string.sub(s, from, to))
            else
                if err then
                    ngx.say("error: ", err)
                    return
                end
                ngx.say("not matched!")
            end
        }
    }
--- request
    GET /re
--- response_body
from: 9
to: 56
matched: <something> <something else> <something further>
--- no_error_log
[error]
