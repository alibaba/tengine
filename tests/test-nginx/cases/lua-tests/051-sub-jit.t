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

=== TEST 1: matched with j
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234 5678", "([0-9]+)", "world", "j")
            if n then
                ngx.say(s, ": ", n)
            else
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, world 5678: 1
--- error_log
pcre JIT compiling result: 1



=== TEST 2: not matched with j
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[0-9]+", "hiya", "j")
            if n then
                ngx.say(s, ": ", n)
            else
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, world: 0
--- error_log
pcre JIT compiling result: 1



=== TEST 3: matched with jo
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234 5678", "([0-9]+)", "world", "jo")
            if n then
                ngx.say(s, ": ", n)
            else
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, world 5678: 1
--- error_log
pcre JIT compiling result: 1



=== TEST 4: not matched with jo
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[0-9]+", "hiya", "jo")
            if n then
                ngx.say(s, ": ", n)
            else
                ngx.say(s)
            end
        ';
    }
--- request
    GET /re
--- response_body
hello, world: 0
--- error_log
pcre JIT compiling result: 1



=== TEST 5: bad pattern
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "hello\\nworld", "(abc", "world", "j")
            if rc then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", s)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: bad argument #2 to '?' (failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc")



=== TEST 6: bad pattern + o
--- config
    location /re {
        content_by_lua '
            local rc, s, n = pcall(ngx.re.sub, "hello\\nworld", "(abc", "world", "jo")
            if rc then
                ngx.say(s, ": ", n)
            else
                ngx.say("error: ", s)
            end
        ';
    }
--- request
    GET /re
--- response_body
error: bad argument #2 to '?' (failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc")

