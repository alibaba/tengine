# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('debug'); # to ensure any log-level can be outputed

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

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



=== TEST 12: regression test print()
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



=== TEST 14: print() in header filter
--- config
    location /log {
        header_filter_by_lua '
            print("hi")
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



=== TEST 15: ngx.log() in header filter
--- config
    location /log {
        header_filter_by_lua '
            ngx.log(ngx.ERR, "hi")
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



=== TEST 16: ngx.log() big data
--- config
    location /log {
        content_by_lua '
            ngx.log(ngx.ERR, "a" .. string.rep("h", 2000) .. "b")
            ngx.say("hi")
        ';
    }
--- request
GET /log
--- response_headers
--- error_log eval
[qr/ah{2000}b/]

