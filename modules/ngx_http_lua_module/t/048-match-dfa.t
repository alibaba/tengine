# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

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

=== TEST 1: matched with d
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello", "(he|hell)", "d")
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
hell
nil
nil



=== TEST 2: matched with d + o
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello", "(he|hell)", "do")
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
hell
nil
nil



=== TEST 3: matched with d + j
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello", "(he|hell)", "jd")
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
hell



=== TEST 4: not matched with j
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("world", "(he|hell)", "d")
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



=== TEST 5: matched with do
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("hello", "he|hell", "do")
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
hell
nil
nil



=== TEST 6: not matched with do
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("world", "([0-9]+)", "do")
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



=== TEST 7: UTF-8 mode without UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("你好", ".", "Ud")
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



=== TEST 8: UTF-8 mode with UTF-8 sequence checks
--- config
    location /re {
        content_by_lua '
            local m = ngx.re.match("你好", ".", "ud")
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
