# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 4);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)")
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
            m = ngx.re.match("hello, 1234", "(\\\\d+)")
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
            m = ngx.re.match("hello, 1234", "(\\d+)")
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
--- error_log eval
[qr/invalid escape sequence near '"\('/]
--- error_code: 500



=== TEST 4: escaping sequences in [[ ... ]]
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "[[\\d+]]")
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
--- error_log eval
[qr/invalid escape sequence near '"\[\['/]
--- error_code: 500



=== TEST 5: single capture
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]{2})[0-9]+")
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
            m = ngx.re.match("hello, 1234", "([a-z]+).*?([0-9]{2})[0-9]+", "")
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



=== TEST 7: multiple captures (with o)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([a-z]+).*?([0-9]{2})[0-9]+", "o")
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



=== TEST 8: not matched
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "foo")
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
            m = ngx.re.match("hello, 1234", "HELLO")
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



=== TEST 10: case sensitive by default
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "HELLO", "i")
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



=== TEST 11: UTF-8 mode
--- config
    location /re {
        content_by_lua '
            rc, err = pcall(ngx.re.match, "hello章亦春", "HELLO.{2}", "iu")
            if not rc then
                ngx.say("FAIL: ", err)
                return
            end
            local m = err
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
^(?:FAIL: bad argument \#2 to '\?' \(failed to compile regex "HELLO\.\{2\}": pcre_compile\(\) failed: this version of PCRE is not compiled with PCRE_UTF8 support in "HELLO\.\{2\}" at "HELLO\.\{2\}"\)|hello章亦)$



=== TEST 12: multi-line mode (^ at line head)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "^world", "m")
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



=== TEST 13: multi-line mode (. does not match \n)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", ".*", "m")
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



=== TEST 14: single-line mode (^ as normal)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "^world", "s")
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



=== TEST 15: single-line mode (dot all)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", ".*", "s")
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



=== TEST 16: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello\\nworld", "\\\\w     \\\\w", "x")
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



=== TEST 17: bad pattern
--- config
    location /re {
        content_by_lua '
            rc, m = pcall(ngx.re.match, "hello\\nworld", "(abc")
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
--- response_body
error: bad argument #2 to '?' (failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc")



=== TEST 18: bad option
--- config
    location /re {
        content_by_lua '
            rc, m = pcall(ngx.re.match, "hello\\nworld", ".*", "H")
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
--- response_body
error: bad argument #3 to '?' (unknown flag "H")



=== TEST 19: extended mode (ignore whitespaces)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "(world)|(hello)", "x")
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
nil
hello



=== TEST 20: optional trailing captures
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)(h?)")
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



=== TEST 21: anchored match (failed)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "a")
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



=== TEST 22: anchored match (succeeded)
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("1234, hello", "([0-9]+)", "a")
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



=== TEST 23: match with ctx but no pos
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            m = ngx.re.match("1234, hello", "([0-9]+)", "", ctx)
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
4



=== TEST 24: match with ctx and a pos
--- config
    location /re {
        content_by_lua '
            local ctx = { pos = 2 }
            m = ngx.re.match("1234, hello", "([0-9]+)", "", ctx)
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
4



=== TEST 25: sanity (set_by_lua)
--- config
    location /re {
        set_by_lua $res '
            m = ngx.re.match("hello, 1234", "([0-9]+)")
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



=== TEST 26: match (look-behind assertion)
--- config
    location /re {
        content_by_lua '
            local ctx = {}
            local m = ngx.re.match("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "", ctx)
            ngx.say(m and m[0])

            m = ngx.re.match("{foobarbaz}", "(?<=foo)bar|(?<=bar)baz", "", ctx)
            ngx.say(m and m[0])
        ';
    }
--- request
    GET /re
--- response_body
bar
baz



=== TEST 27: escaping sequences
--- config
    location /re {
        content_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
m = ngx.re.match("hello, 1234", "(\\\s+)")
if m then
    ngx.say("[", m[0], "]")
else
    ngx.say("not matched!")
end
--- request
    GET /re
--- response_body_like: 500 Internal Server Error
--- error_log eval
[qr/invalid escape sequence near '"\(\\'/]
--- error_code: 500



=== TEST 28: escaping sequences
--- config
    location /re {
        access_by_lua_file html/a.lua;
        content_by_lua return;
    }
--- user_files
>>> a.lua
local uri = "<impact>2</impact>"
local regex = '(?:>[\\w\\s]*</?\\w{2,}>)';
ngx.say("regex: ", regex)
m = ngx.re.match(uri, regex, "oi")
if m then
    ngx.say("[", m[0], "]")
else
    ngx.say("not matched!")
end
--- request
    GET /re
--- response_body
regex: (?:>[\w\s]*</?\w{2,}>)
[>2</impact>]



=== TEST 29: long brackets
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", [[\\d+]])
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



=== TEST 30: bad pattern
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+")
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
--- error_log chop
lua handler aborted: runtime error: [string "content_by_lua"]:2: bad argument #2 to 'match' (failed to compile regex "([0-9]+": pcre_compile() failed: missing ) in "([0-9]+")



=== TEST 31: long brackets containing [...]
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", [[([0-9]+)]])
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



=== TEST 32: bug report (github issue #72)
--- config
    location /re {
        content_by_lua '
            ngx.re.match("hello", "hello", "j")
            ngx.say("done")
        ';
        header_filter_by_lua '
            ngx.re.match("hello", "world", "j")
        ';
    }
--- request
    GET /re
--- response_body
done



=== TEST 33: bug report (github issue #72)
--- config
    location /re {
        content_by_lua '
            ngx.re.match("hello", "hello", "j")
            ngx.exec("/foo")
        ';
    }

    location /foo {
        content_by_lua '
            ngx.re.match("hello", "world", "j")
            ngx.say("done")
        ';
    }
--- request
    GET /re
--- response_body
done

