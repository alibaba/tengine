# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('debug');

repeat_each(2);

plan tests => repeat_each() * 34;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sleep 0.5 - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.sleep(0.5)
            local now = ngx.now()
            ngx.say(now - before)
        ';
    }
--- request
GET /test
--- response_body_like chop
^0\.(?:4[5-9]\d*|5[0-5]\d*|5)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
lua sleep timer expired: "/test?"



=== TEST 2: sleep a - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.sleep("a")
            local now = ngx.now()
            ngx.say(now - before)
        ';
    }
--- request
GET /test
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log
bad argument #1 to 'sleep'



=== TEST 3: sleep 0.5 in subrequest - content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local before = ngx.now()
            ngx.location.capture("/sleep")
            local now = ngx.now()
            local delay = now - before
            ngx.say(delay)
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep(0.5)';
    }
--- request
GET /test
--- response_body_like chop
^0\.(?:4[5-9]\d*|5[0-9]\d*|5)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/sleep?"
--- no_error_log
[error]



=== TEST 4: sleep a in subrequest with bad argument
--- config
    location /test {
        content_by_lua '
            local res = ngx.location.capture("/sleep");
        ';
    }
    location /sleep {
        content_by_lua 'ngx.sleep("a")';
    }
--- request
GET /test
--- response_body_like:
--- error_log
bad argument #1 to 'sleep'



=== TEST 5: sleep 0.33 - multi-times in content
--- config
    location /test {
        content_by_lua '
            ngx.update_time()
            local start = ngx.now()
            ngx.sleep(0.33)
            ngx.sleep(0.33)
            ngx.sleep(0.33)
            ngx.say(ngx.now() - start)
        ';
    }
--- request
GET /test
--- response_body_like chop
^(?:0\.9\d*|1\.[0-2]\d*|1)$
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 6: sleep 0.5 - interleaved by ngx.say() - ended by ngx.sleep
--- config
    location /test {
        content_by_lua '
            ngx.send_headers()
            -- ngx.location.capture("/sleep")
            ngx.sleep(1)
            ngx.say("blah")
            ngx.sleep(1)
            -- ngx.location.capture("/sleep")
        ';
    }
    location = /sleep {
        echo_sleep 0.1;
    }
--- request
GET /test
--- response_body
blah
--- error_log
lua ready to sleep
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 7: sleep 0.5 - interleaved by ngx.say() - not ended by ngx.sleep
--- config
    location /test {
        content_by_lua '
            ngx.send_headers()
            -- ngx.location.capture("/sleep")
            ngx.sleep(0.3)
            ngx.say("blah")
            ngx.sleep(0.5)
            -- ngx.location.capture("/sleep")
            ngx.say("hiya")
        ';
    }
    location = /sleep {
        echo_sleep 0.1;
    }
--- request
GET /test
--- response_body
blah
hiya
--- error_log
lua ready to sleep for
lua sleep timer expired: "/test?"
--- no_error_log
[error]



=== TEST 8: ngx.location.capture before and after ngx.sleep
--- config
    location /test {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)

            ngx.sleep(0.1)

            res = ngx.location.capture("/sub")
            ngx.print(res.body)
        ';
    }
    location = /hello {
        echo hello world;
    }
    location = /sub {
        proxy_pass http://127.0.0.1:$server_port/hello;
    }
--- request
GET /test
--- response_body
hello world
hello world
--- no_error_log
[error]

