# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('debug'); # to ensure any log-level can be outputed

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 4);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: test log-level STDERR
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.STDERR, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 2: test log-level EMERG
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.EMERG, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[emerg\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 3: test log-level ALERT
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.ALERT, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[alert\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 4: test log-level CRIT
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.CRIT, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[crit\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 5: test log-level ERR
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.ERR, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 6: test log-level WARN
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.WARN, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[warn\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 7: test log-level NOTICE
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.NOTICE, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[notice\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 8: test log-level INFO
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.INFO, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[info\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 9: test log-level DEBUG
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            ngx.log(ngx.DEBUG, "hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[debug\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 10: regression test print()
--- config
    location /log {
        content_by_lua '
            ngx.say("before log")
            print("hello, log", 1234, 3.14159)
            ngx.say("after log")
        ';
    }
--- request
GET /log
--- response_body
before log
after log
--- error_log eval
qr/\[notice\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:3: hello, log12343.14159/



=== TEST 11: print(nil)
--- config
    location /log {
        content_by_lua '
            print()
            print(nil)
            print("nil: ", nil)
            ngx.say("hi");
        ';
    }
--- request
GET /log
--- response_body
hi
--- error_log eval
[
'[lua] [string "content_by_lua"]:2: ,',
'[lua] [string "content_by_lua"]:3: nil,',
'[lua] [string "content_by_lua"]:4: nil: nil,',
]



=== TEST 12: ngx.log in set_by_lua
--- config
    location /log {
        set_by_lua $a '
            ngx.log(ngx.ERR, "HELLO")
            return 32;
        ';
        echo $a;
    }
--- request
GET /log
--- response_body
32
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] \[string "set_by_lua"\]:2: HELLO,/



=== TEST 13: test booleans and nil
--- config
    location /log {
        set_by_lua $a '
            ngx.log(ngx.ERR, true, false, nil)
            return 32;
        ';
        echo $a;
    }
--- request
GET /log
--- response_body
32
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] \[string "set_by_lua"\]:2: truefalsenil,/



=== TEST 14: print() in header filter
--- config
    location /log {
        header_filter_by_lua '
            print("hello world")
            ngx.header.foo = 32
        ';
        echo hi;
    }
--- request
GET /log
--- response_headers
foo: 32
--- error_log eval
qr/\[notice\] .*? \[lua\] \[string "header_filter_by_lua"\]:2: hello world/
--- response_body
hi



=== TEST 15: ngx.log() in header filter
--- config
    location /log {
        header_filter_by_lua '
            ngx.log(ngx.ERR, "howdy, lua!")
            ngx.header.foo = 32
        ';
        echo hi;
    }
--- request
GET /log
--- response_headers
foo: 32
--- response_body
hi
--- error_log eval
qr/\[error\] .*? \[lua\] \[string "header_filter_by_lua"\]:2: howdy, lua!/



=== TEST 16: ngx.log() big data
--- config
    location /log {
        content_by_lua '
            ngx.log(ngx.ERR, "a" .. string.rep("h", 1970) .. "b")
            ngx.say("hi")
        ';
    }
--- request
GET /log
--- response_headers
--- error_log eval
[qr/ah{1970}b/]



=== TEST 17: ngx.log in Lua function calls & inlined lua
--- config
    location /log {
        content_by_lua '
            function foo()
                bar()
            end

            function bar()
                ngx.log(ngx.ERR, "hello, log", 1234, 3.14159)
            end

            foo()
            ngx.say("done")
        ';
    }
--- request
GET /log
--- response_body
done
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:7: bar\(\): hello, log12343.14159/



=== TEST 18: ngx.log in Lua function tail-calls & inlined lua
--- config
    location /log {
        content_by_lua '
            function foo()
                return bar(5)
            end

            function bar(n)
                if n < 1 then
                    ngx.log(ngx.ERR, "hello, log", 1234, 3.14159)
                    return n
                end

                return bar(n - 1)
            end

            foo()
            ngx.say("done")
        ';
    }
--- request
GET /log
--- response_body
done
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] \[string "content_by_lua"\]:8:(?: foo\(\):)? hello, log12343.14159/



=== TEST 19: ngx.log in Lua files
--- config
    location /log {
        content_by_lua_file 'html/test.lua';
    }
--- user_files
>>> test.lua
function foo()
    bar()
end

function bar()
    ngx.log(ngx.ERR, "hello, log", 1234, 3.14159)
end

foo()
ngx.say("done")

--- request
GET /log
--- response_body
done
--- error_log eval
qr/\[error\] \S+: \S+ \[lua\] test.lua:6: bar\(\): hello, log12343.14159/



=== TEST 20: ngx.log with bad levels (ngx.ERROR, -1)
--- config
    location /log {
        content_by_lua '
            ngx.log(ngx.ERROR, "hello lua")
            ngx.say("done")
        ';
    }
--- request
GET /log
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad log level: -1



=== TEST 21: ngx.log with bad levels (9)
--- config
    location /log {
        content_by_lua '
            ngx.log(9, "hello lua")
            ngx.say("done")
        ';
    }
--- request
GET /log
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad log level: 9



=== TEST 22: \0 in the log message
--- config
    location = /t {
        content_by_lua '
            ngx.log(ngx.WARN, "hello\\0world")
            ngx.say("ok")
        ';
    }
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
--- error_log eval
"2: hello\0world, client: "

