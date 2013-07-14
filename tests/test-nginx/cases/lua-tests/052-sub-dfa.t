# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: matched with d
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234 5678", "[0-9]|[0-9][0-9]", "world", "d")
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
hello, world34 5678: 1



=== TEST 2: not matched with d
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[0-9]+", "hiya", "d")
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



=== TEST 3: matched with do
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, 1234 5678", "[0-9]|[0-9][0-9]", "world", "do")
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
hello, world34 5678: 1



=== TEST 4: not matched with do
--- config
    location /re {
        content_by_lua '
            local s, n = ngx.re.sub("hello, world", "[0-9]+", "hiya", "do")
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



=== TEST 5: bad pattern
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("hello\\nworld", "(abc", "world", "j")
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
error: failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]



=== TEST 6: bad pattern + o
--- config
    location /re {
        content_by_lua '
            local s, n, err = ngx.re.sub("hello\\nworld", "(abc", "world", "jo")
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
error: failed to compile regex "(abc": pcre_compile() failed: missing ) in "(abc"
--- no_error_log
[error]

