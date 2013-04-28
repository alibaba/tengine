# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 5);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "j")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 2: not matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "([0-9]+)", "j")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 3: matched with jo
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, 1234", "([0-9]+)", "jo")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 4: not matched with jo
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello, world", "([0-9]+)", "jo")
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
--- error_log
pcre JIT compiling result: 1



=== TEST 5: bad pattern
--- config
    location /re {
        content_by_lua '
            local m, err = ngx.re.match("hello\\nworld", "(abc", "j")
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
error: failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]

