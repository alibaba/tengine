# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3 + 8);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua '
            ngx.ctx.foo = 32;
            ngx.say(ngx.ctx.foo)
        ';
    }
--- request
GET /lua
--- response_body
32
--- no_error_log
[error]



=== TEST 2: rewrite, access, and content
--- config
    location /lua {
        rewrite_by_lua '
            print("foo = ", ngx.ctx.foo)
            ngx.ctx.foo = 76
        ';
        access_by_lua '
            ngx.ctx.foo = ngx.ctx.foo + 3
        ';
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }
--- request
GET /lua
--- response_body
79
--- no_error_log
[error]
--- grep_error_log eval: qr/foo = [^,]+/
--- log_level: info
--- grep_error_log_out
foo = nil



=== TEST 3: interal redirect clears ngx.ctx
--- config
    location /echo {
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }
    location /lua {
        content_by_lua '
            ngx.ctx.foo = ngx.var.arg_data
            -- ngx.say(ngx.ctx.foo)
            ngx.exec("/echo")
        ';
    }
--- request
GET /lua?data=hello
--- response_body
nil
--- no_error_log
[error]



=== TEST 4: subrequest has its own ctx
--- config
    location /sub {
        content_by_lua '
            ngx.say("sub pre: ", ngx.ctx.blah)
            ngx.ctx.blah = 32
            ngx.say("sub post: ", ngx.ctx.blah)
        ';
    }
    location /main {
        content_by_lua '
            ngx.ctx.blah = 73
            ngx.say("main pre: ", ngx.ctx.blah)
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("main post: ", ngx.ctx.blah)
        ';
    }
--- request
    GET /main
--- response_body
main pre: 73
sub pre: nil
sub post: 32
main post: 73
--- no_error_log
[error]



=== TEST 5: overriding ctx
--- config
    location /lua {
        content_by_lua '
            ngx.ctx = { foo = 32, bar = 54 };
            ngx.say(ngx.ctx.foo)
            ngx.say(ngx.ctx.bar)

            ngx.ctx = { baz = 56  };
            ngx.say(ngx.ctx.foo)
            ngx.say(ngx.ctx.baz)
        ';
    }
--- request
GET /lua
--- response_body
32
54
nil
56
--- no_error_log
[error]



=== TEST 6: header filter
--- config
    location /lua {
        content_by_lua '
            ngx.ctx.foo = 32;
            ngx.say(ngx.ctx.foo)
        ';
        header_filter_by_lua '
            ngx.header.blah = ngx.ctx.foo + 1
        ';
    }
--- request
GET /lua
--- response_headers
blah: 33
--- response_body
32
--- no_error_log
[error]



=== TEST 7: capture_multi
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.ctx.dog)
        ';
    }

    location /lua {
        set $dog 'blah';
        set $cat 'foo';
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                {"/other/1",
                    { ctx = { dog = "hello" }}
                },
                {"/other/2",
                    { ctx = { dog = "hiya" }}
                }
            };

            ngx.print(res1.body)
            ngx.print(res2.body)
            ngx.say("parent: ", ngx.ctx.dog)
        ';
    }
--- request
GET /lua
--- response_body
dog = hello
dog = hiya
parent: nil
--- no_error_log
[error]



=== TEST 8: set_by_lua
--- config
    location /lua {
        set_by_lua $bar 'ngx.ctx.foo = 3 return 4';
        set_by_lua $foo 'return ngx.ctx.foo';
        echo "foo = $foo, bar = $bar";
    }
--- request
GET /lua
--- response_body
foo = 3, bar = 4
--- no_error_log
[error]



=== TEST 9: ngx.ctx leaks with ngx.exec + log_by_lua
--- config
    location = /t {
        content_by_lua '
            ngx.ctx.foo = 32;
            ngx.exec("/f")
        ';
        log_by_lua 'ngx.log(ngx.WARN, "ctx.foo = ", ngx.ctx.foo)';
    }
    location = /f {
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }
--- request
GET /t
--- response_body
nil
--- no_error_log
[error]
ctx.foo = 



=== TEST 10: memory leaks with ngx.ctx + ngx.req.set_uri + log_by_lua
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = 32;
            ngx.req.set_uri("/f", true)
        ';
        log_by_lua 'ngx.log(ngx.WARN, "ctx.foo = ", ngx.ctx.foo)';
    }
    location = /f {
        content_by_lua '
            ngx.say(ngx.ctx.foo)
        ';
    }
--- request
GET /t
--- response_body
nil
--- no_error_log
[error]
ctx.foo = 



=== TEST 11: ngx.ctx + ngx.exit(ngx.ERROR) + log_by_lua
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = 32;
            ngx.exit(ngx.ERROR)
        ';
        log_by_lua 'ngx.log(ngx.WARN, "ngx.ctx = ", ngx.ctx.foo)';
    }
--- request
GET /t
--- ignore_response
--- no_error_log
[error]
--- error_log
ngx.ctx = 32



=== TEST 12: ngx.ctx + ngx.exit(200) + log_by_lua
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = 32;
            ngx.say(ngx.ctx.foo)
            ngx.exit(200)
        ';
        log_by_lua 'ngx.log(ngx.WARN, "ctx.foo = ", ngx.ctx.foo)';
    }
--- request
GET /t
--- response_body
32
--- no_error_log
[error]
--- error_log
ctx.foo = 32



=== TEST 13: ngx.ctx + ngx.redirect + log_by_lua
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = 32;
            ngx.redirect("/f")
        ';
        log_by_lua 'ngx.log(ngx.WARN, "ngx.ctx.foo = ", 32)';
    }
--- request
GET /t
--- response_body_like: 302 Found
--- error_code: 302
--- error_log
ctx.foo = 32
--- no_error_log
[error]



=== TEST 14: set ngx.ctx before internal redirects performed by other nginx modules
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = "hello world";
        ';
        echo_exec /foo;
    }

    location = /foo {
        echo hello;
    }
--- request
GET /t
--- response_body
hello
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua release ngx.ctx at ref



=== TEST 15: set ngx.ctx before internal redirects performed by other nginx modules (with log_by_lua)
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = "hello world";
        ';
        echo_exec /foo;
    }

    location = /foo {
        echo hello;
        log_by_lua return;
    }
--- request
GET /t
--- response_body
hello
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua release ngx.ctx at ref



=== TEST 16: set ngx.ctx before simple uri rewrite performed by other nginx modules
--- config
    location = /t {
        set_by_lua $a 'ngx.ctx.foo = "hello world"; return 1';
        rewrite ^ /foo last;
        echo blah;
    }

    location = /foo {
        echo foo;
    }
--- request
GET /t
--- response_body
foo
--- no_error_log
[error]
--- log_level: debug
--- error_log
lua release ngx.ctx at ref



=== TEST 17: ngx.ctx gets prematurely released ngx.exit()
--- config
    location = /t {
        rewrite_by_lua '
            ngx.ctx.foo = 3
        ';
        content_by_lua '
            -- if ngx.headers_sent ~= true then ngx.send_headers() end
            return ngx.exit(200)
        ';
        header_filter_by_lua '
            if ngx.ctx.foo ~= 3 then
                ngx.log(ngx.ERR, "bad ngx.ctx.foo: ", ngx.ctx.foo)
            end
        ';
        }
--- request
    GET /t
--- response_body
--- no_error_log
[error]



=== TEST 18: ngx.ctx gets prematurely released ngx.exit() (lua_code_cache off)
--- config
    location = /t {
        lua_code_cache off;
        rewrite_by_lua '
            ngx.ctx.foo = 3
        ';
        content_by_lua '
            -- if ngx.headers_sent ~= true then ngx.send_headers() end
            return ngx.exit(200)
        ';
        header_filter_by_lua '
            if ngx.ctx.foo ~= 3 then
                ngx.log(ngx.ERR, "bad ngx.ctx.foo: ", ngx.ctx.foo)
            end
        ';
        }
--- request
    GET /t
--- response_body
--- no_error_log
[error]
