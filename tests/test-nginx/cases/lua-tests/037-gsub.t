# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 10);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("[hello, world]", "[a-z]+", "howdy")
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
            local s, n = ngx.re.gsub("hello, world", "[a-z]+", "howdy")
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
            local s, n = ngx.re.gsub("hello, world", "[A-Z]+", "howdy")
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

            local s, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", f)
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

            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", f)
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
            local s, n = ngx.re.gsub("hello, world", "([a-z])[a-z]+", "[$0,$1]")
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
            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", "[$0,$1]")
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

            local s, n = ngx.re.gsub("{hello, world}", "([a-z])[a-z]+", f)
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
            local s, n = ngx.re.gsub("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "h$0")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
{foohbarhbaz}
2



=== TEST 10: gsub with a patch matching an empty substring (string template)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("hello", "a|", "b")
            ngx.say("s: ", s)
            ngx.say("n: ", n)
        ';
    }
--- request
    GET /re
--- response_body
s: bhbeblblbob
n: 6
--- no_error_log
[error]



=== TEST 11: gsub with a patch matching an empty substring (string template, empty subj)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("", "a|", "b")
            ngx.say("s: ", s)
            ngx.say("n: ", n)
        ';
    }
--- request
    GET /re
--- response_body
s: b
n: 1
--- no_error_log
[error]



=== TEST 12: gsub with a patch matching an empty substring (func)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("hello", "a|", function () return "b" end)
            ngx.say("s: ", s)
            ngx.say("n: ", n)
        ';
    }
--- request
    GET /re
--- response_body
s: bhbeblblbob
n: 6
--- no_error_log
[error]



=== TEST 13: gsub with a patch matching an empty substring (func, empty subj)
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("", "a|", function () return "b" end)
            ngx.say("s: ", s)
            ngx.say("n: ", n)
        ';
    }
--- request
    GET /re
--- response_body
s: b
n: 1
--- no_error_log
[error]



=== TEST 14: big subject string exceeding the luabuf chunk size (with trailing unmatched data, func repl)
--- config
    location /re {
        content_by_lua '
            local subj = string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. "aaa"

            local function repl(m)
                return string.rep("c", string.len(m[0]))
            end

            local s, n = ngx.re.gsub(subj, "b+", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body eval
("a" x 8000) . ("c" x 1000) . ("a" x 8000) . ("c" x 1000)
. "aaa
2
"
--- no_error_log
[error]



=== TEST 15: big subject string exceeding the luabuf chunk size (without trailing unmatched data, func repl)
--- config
    location /re {
        content_by_lua '
            local subj = string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. string.rep("a", 8000)
                .. string.rep("b", 1000)

            local function repl(m)
                return string.rep("c", string.len(m[0]))
            end

            local s, n = ngx.re.gsub(subj, "b+", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body eval
("a" x 8000) . ("c" x 1000) . ("a" x 8000) . ("c" x 1000)
. "\n2\n"
--- no_error_log
[error]



=== TEST 16: big subject string exceeding the luabuf chunk size (with trailing unmatched data, str repl)
--- config
    location /re {
        content_by_lua '
            local subj = string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. "aaa"

            local s, n = ngx.re.gsub(subj, "b(b+)(b)", "$1 $2")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body eval
("a" x 8000) . ("b" x 998) . " b" . ("a" x 8000) . ("b" x 998) . " baaa
2
"
--- no_error_log
[error]



=== TEST 17: big subject string exceeding the luabuf chunk size (without trailing unmatched data, str repl)
--- config
    location /re {
        content_by_lua '
            local subj = string.rep("a", 8000)
                .. string.rep("b", 1000)
                .. string.rep("a", 8000)
                .. string.rep("b", 1000)

            local s, n = ngx.re.gsub(subj, "b(b+)(b)", "$1 $2")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body eval
("a" x 8000) . ("b" x 998) . " b" . ("a" x 8000) . ("b" x 998) . " b\n2\n"
--- no_error_log
[error]



=== TEST 18: named pattern repl w/ callback
--- config
    location /re {
       content_by_lua '
            local repl = function (m)
                return "[" .. m[0] .. "," .. m["first"] .. "]"
            end

            local s, n = ngx.re.gsub("hello, world", "(?<first>[a-z])[a-z]+", repl)
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[hello,h], [world,w]
2



=== TEST 19: $0 without parens
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.gsub("a b c d", [[\w]], "[$0]")
            ngx.say(s)
            ngx.say(n)
        ';
    }
--- request
    GET /re
--- response_body
[a] [b] [c] [d]
4
--- no_error_log
[error]



=== TEST 20: bad UTF-8
--- config
    location = /t {
        content_by_lua '
            local target = "你好"
            local regex = "你好"

            -- Note the D here
            local s, n, err = ngx.re.gsub(string.sub(target, 1, 4), regex, "", "u")

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

