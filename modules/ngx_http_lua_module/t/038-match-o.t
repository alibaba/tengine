# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]+)", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234



=== TEST 2: escaping sequences
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "(\\\\d+)", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234



=== TEST 3: escaping sequences (bad)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "(\\d+)", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
[qr/invalid escape sequence near '"\('/]



=== TEST 4: escaping sequences in [[ ... ]]
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "[[\\d+]]", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
[qr/invalid escape sequence near '"\[\['/]



=== TEST 5: single capture
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]{2})[0-9]+", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234
12



=== TEST 6: multiple captures
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([a-z]+).*?([0-9]{2})[0-9]+", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
hello
12



=== TEST 7: not matched
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "foo", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 8: case sensitive by default
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "HELLO", "o")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 9: case sensitive by default
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "HELLO", "oi")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 10: UTF-8 mode
--- config
    location /re {
        content_by_lua '
            local rc, m = pcall(ngx.re.match, "hello章亦春", "HELLO.{2}", "iou")
            if not rc then
                ngx.say("error: ", m)
                return
            end
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body_like chop
this version of PCRE is not compiled with PCRE_UTF8 support|^hello章亦$



=== TEST 11: multi-line mode (^ at line head)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello\\nworld", "^world", "mo")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
world



=== TEST 12: multi-line mode (. does not match \n)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello\\nworld", ".*", "om")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 13: single-line mode (^ as normal)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello\\nworld", "^world", "so")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched: nil



=== TEST 14: single-line mode (dot all)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello\\nworld", ".*", "os")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
world



=== TEST 15: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello\\nworld", "\\\\w     \\\\w", "xo")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
he



=== TEST 16: bad pattern
--- config
    location /re {
        content_by_lua '
            local m, err = ngx.re.match("hello\\nworld", "(abc", "o")
            if m then
                ngx.say(m[0])

            else
                if err then
                    ngx.say("error: ", err)

                else
                    ngx.say("not matched: ", m)
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



=== TEST 17: bad option
--- config
    location /re {
        content_by_lua '
            local rc, m = pcall(ngx.re.match, "hello\\nworld", ".*", "Ho")
            if rc then
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            else
                ngx.say("error: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body_like chop
^error: .*?unknown flag "H"



=== TEST 18: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, world", "(world)|(hello)", "xo")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched: ", m)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
false
hello



=== TEST 19: optional trailing captures
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]+)(h?)", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body eval
"1234
1234

"



=== TEST 20: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]+)", "oa")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
not matched!



=== TEST 21: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("1234, hello", "([0-9]+)", "ao")
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234



=== TEST 22: match with ctx but no pos
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local m = ngx.re.match("1234, hello", "([0-9]+)", "o", ctx)
            if m then
                ngx.say(m[0])
                ngx.say(ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say(ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
1234
5



=== TEST 23: match with ctx and a pos
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 3 }
            local m = ngx.re.match("1234, hello", "([0-9]+)", "o", ctx)
            if m then
                ngx.say(m[0])
                ngx.say(ctx.pos)
            else
                ngx.say("not matched!")
                ngx.say(ctx.pos)
            end
        ';
    }
--- request
    GET /re
--- response_body
34
5



=== TEST 24: sanity (set_by_lua)
--- config
    location /re {
        set_by_lua $res '
            local m = ngx.re.match("hello, 1234", "([0-9]+)", "o")
            if m then
                return m[0]
            else
                return "not matched!"
            end
        ';
        echo $res;
    }
--- request
    GET /re
--- response_body
1234



=== TEST 25: match (look-behind assertion)
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local m = ngx.re.match("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "o", ctx)
            ngx.say(m and m[0])

            m = ngx.re.match("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "o", ctx)
            ngx.say(m and m[0])
        ';
    }
--- request
    GET /re
--- response_body
bar
baz



=== TEST 26: match (with regex cache)
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([A-Z]+)", "io")
            ngx.say(m and m[0])

            m = ngx.re.match("1234, okay", "([A-Z]+)", "io")
            ngx.say(m and m[0])

            m = ngx.re.match("hello, 1234", "([A-Z]+)", "o")
            ngx.say(m and m[0])
        ';
    }
--- request
    GET /re
--- response_body
hello
okay
nil



=== TEST 27: match (with regex cache and ctx)
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local m = ngx.re.match("hello, 1234", "([A-Z]+)", "io", ctx)
            ngx.say(m and m[0])
            ngx.say(ctx.pos)

            m = ngx.re.match("1234, okay", "([A-Z]+)", "io", ctx)
            ngx.say(m and m[0])
            ngx.say(ctx.pos)

            ctx.pos = 1
            m = ngx.re.match("hi, 1234", "([A-Z]+)", "o", ctx)
            ngx.say(m and m[0])
            ngx.say(ctx.pos)
        ';
    }
--- request
    GET /re
--- response_body
hello
6
okay
11
nil
1



=== TEST 28: exceeding regex cache max entries
--- http_config
    lua_regex_cache_max_entries 2;
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]+)", "o")
            ngx.say(m and m[0])

            m = ngx.re.match("howdy, 567", "([0-9]+)", "oi")
            ngx.say(m and m[0])

            m = ngx.re.match("hiya, 98", "([0-9]+)", "ox")
            ngx.say(m and m[0])
        ';
    }
--- request
    GET /re
--- response_body
1234
567
98



=== TEST 29: disable regex cache completely
--- http_config
    lua_regex_cache_max_entries 0;
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "([0-9]+)", "o")
            ngx.say(m and m[0])

            m = ngx.re.match("howdy, 567", "([0-9]+)", "oi")
            ngx.say(m and m[0])

            m = ngx.re.match("hiya, 98", "([0-9]+)", "ox")
            ngx.say(m and m[0])
        ';
    }
--- request
    GET /re
--- response_body
1234
567
98



=== TEST 30: named subpatterns w/ extraction
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "(?<first>[a-z]+), [0-9]+", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m.first)
                ngx.say(m.second)
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
hello
hello
nil



=== TEST 31: duplicate named subpatterns w/ extraction
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, 1234", "(?<first>[a-z]+), (?<first>[0-9]+)", "Do")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
                ngx.say(table.concat(m.first,"-"))
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, 1234
hello
1234
hello-1234



=== TEST 32: named captures are empty strings
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("1234", "(?<first>[a-z]*)([0-9]+)", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m.first)
                ngx.say(m[1])
                ngx.say(m[2])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
1234


1234



=== TEST 33: named captures are false
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello, world", "(world)|(hello)|(?<named>howdy)", "o")
            if m then
                ngx.say(m[0])
                ngx.say(m[1])
                ngx.say(m[2])
                ngx.say(m[3])
                ngx.say(m["named"])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
false
hello
false
false
