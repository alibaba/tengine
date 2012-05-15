# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: matched with d
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello", "(he|hell)", "d")
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



=== TEST 2: matched with d + j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello", "(he|hell)", "jd")
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



=== TEST 3: not matched with j
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("world", "(he|hell)", "d")
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



=== TEST 4: matched with do
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("hello", "he|hell", "do")
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



=== TEST 5: not matched with do
--- config
    location /re {
        content_by_lua '
            m = ngx.re.match("world", "([0-9]+)", "do")
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

