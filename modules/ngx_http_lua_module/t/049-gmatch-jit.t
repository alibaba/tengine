# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 9);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: gmatch matched
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, world", "[a-z]+", "j") do
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
--- error_log
pcre JIT compiling result: 1



=== TEST 2: fail to match
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[0-9]", "j")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 3: gmatch matched but no iterate
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "j")
            ngx.say("done")
        ';
    }
--- request
    GET /re
--- response_body
done
--- error_log
pcre JIT compiling result: 1



=== TEST 4: gmatch matched but only iterate once and still matches remain
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "j")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 5: gmatch matched + o
--- config
    location /re {
        content_by_lua '
            for m in ngx.re.gmatch("hello, world", "[a-z]+", "jo") do
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

--- grep_error_log eval
qr/pcre JIT compiling result: \d+/

--- grep_error_log_out eval
["pcre JIT compiling result: 1\n", ""]



=== TEST 6: fail to match + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[0-9]", "jo")
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

--- grep_error_log eval
qr/pcre JIT compiling result: \d+/

--- grep_error_log_out eval
["pcre JIT compiling result: 1\n", ""]



=== TEST 7: gmatch matched but no iterate + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "jo")
            ngx.say("done")
        ';
    }
--- request
    GET /re
--- response_body
done

--- grep_error_log eval
qr/pcre JIT compiling result: \d+/

--- grep_error_log_out eval
["pcre JIT compiling result: 1\n", ""]



=== TEST 8: gmatch matched but only iterate once and still matches remain + o
--- config
    location /re {
        content_by_lua '
            local it = ngx.re.gmatch("hello, world", "[a-z]+", "jo")
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

--- grep_error_log eval
qr/pcre JIT compiling result: \d+/

--- grep_error_log_out eval
["pcre JIT compiling result: 1\n", ""]



=== TEST 9: bad pattern
--- config
    location /re {
        content_by_lua '
            local m, err = ngx.re.gmatch("hello\\nworld", "(abc", "j")
            if not m then
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
