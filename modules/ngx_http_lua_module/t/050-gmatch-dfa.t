# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 5);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: gmatch matched
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, halo", "h[a-z]|h[a-z][a-z]", "d") do
                if m then
                    ngx.say(m[0])
                    ngx.say(m[1])
                else
                    ngx.say("not matched: ", m)
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hel
nil
hal
nil



=== TEST 2: d + j
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, halo", "h[a-z]|h[a-z][a-z]", "dj") do
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hel
hal



=== TEST 3: fail to match
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[0-9]", "d")
            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end
        ';
    }
--- request
    GET /re
--- response_body
nil
nil
nil



=== TEST 4: gmatch matched but no iterate
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "d")
            ngx.say("done")
        ';
    }
--- request
    GET /re
--- response_body
done



=== TEST 5: gmatch matched but only iterate once and still matches remain
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "d")
            local m = it()
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 6: gmatch matched + o
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, world", "[a-z]+", "do") do
                if m then
                    ngx.say(m[0])
                else
                    ngx.say("not matched: ", m)
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hello
world



=== TEST 7: fail to match + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[0-9]", "do")
            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end

            local m = it()
            if m then ngx.say(m[0]) else ngx.say(m) end
        ';
    }
--- request
    GET /re
--- response_body
nil
nil
nil



=== TEST 8: gmatch matched but no iterate + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "do")
            ngx.say("done")
        ';
    }
--- request
    GET /re
--- response_body
done



=== TEST 9: gmatch matched but only iterate once and still matches remain + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "do")
            local m = it()
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched")
            end
        ';
    }
--- request
    GET /re
--- response_body
hello



=== TEST 10: bad pattern
--- config
    location /re {
        content_by_lua '
            local it, err = ngx.re.gmatch("hello\\nworld", "(abc", "d")
            if not it then
                ngx.say("error: ", err)
                return
            end
            ngx.say("success")
        ';
    }
--- request
    GET /re
--- response_body
error: pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]



=== TEST 11: UTF-8 mode without UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("你好", ".", "Ud")
            local m = it()
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- stap
probe process("$LIBPCRE_PATH").function("pcre_compile") {
    printf("compile opts: %x\n", $options)
}

probe process("$LIBPCRE_PATH").function("pcre_dfa_exec") {
    printf("exec opts: %x\n", $options)
}

--- stap_out
compile opts: 800
exec opts: 2000

--- request
    GET /re
--- response_body
你
--- no_error_log
[error]



=== TEST 12: UTF-8 mode with UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("你好", ".", "ud")
            local m = it()
            if m then
                ngx.say(m[0])
            else
                ngx.say("not matched!")
            end
        ';
    }
--- stap
probe process("$LIBPCRE_PATH").function("pcre_compile") {
    printf("compile opts: %x\n", $options)
}

probe process("$LIBPCRE_PATH").function("pcre_dfa_exec") {
    printf("exec opts: %x\n", $options)
}

--- stap_out
compile opts: 800
exec opts: 0

--- request
    GET /re
--- response_body
你
--- no_error_log
[error]



=== TEST 13: gmatched with submatch captures
--- config
    location /re {
        content_by_lua '
            for m in  ngx.re.gmatch("hello", "(he|hell)", "d") do
                if m then
                    ngx.say(m[0])
                    ngx.say(m[1])
                    ngx.say(m[2])
                else
                    ngx.say("not matched!")
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hell
nil
nil



=== TEST 14: gmatched with submatch captures (compile once)
--- config
    location /re {
        content_by_lua '
            for m in  ngx.re.gmatch("hello", "(he|hell)", "od") do
                if m then
                    ngx.say(m[0])
                    ngx.say(m[1])
                    ngx.say(m[2])
                else
                    ngx.say("not matched!")
                end
            end
        ';
    }
--- request
    GET /re
--- response_body
hell
nil
nil
