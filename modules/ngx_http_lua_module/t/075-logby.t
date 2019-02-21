# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
log_level('debug');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 10);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: log_by_lua
--- config
    location /lua {
        echo hello;
        log_by_lua 'ngx.log(ngx.ERR, "Hello from log_by_lua: ", ngx.var.uri)';
    }
--- request
GET /lua
--- response_body
hello
--- error_log
Hello from log_by_lua: /lua



=== TEST 2: log_by_lua_file
--- config
    location /lua {
        echo hello;
        log_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "Hello from log_by_lua: ", ngx.var.uri)
--- request
GET /lua
--- response_body
hello
--- error_log
Hello from log_by_lua: /lua



=== TEST 3: log_by_lua_file & content_by_lua
--- config
    location /lua {
        set $counter 3;
        content_by_lua 'ngx.var.counter = ngx.var.counter + 1 ngx.say(ngx.var.counter)';
        log_by_lua_file html/a.lua;
    }
--- user_files
>>> a.lua
ngx.log(ngx.ERR, "Hello from log_by_lua: ", ngx.var.counter * 2)
--- request
GET /lua
--- response_body
4
--- error_log
Hello from log_by_lua: 8



=== TEST 4: ngx.ctx available in log_by_lua (already defined)
--- config
    location /lua {
        content_by_lua 'ngx.ctx.counter = 3 ngx.say(ngx.ctx.counter)';
        log_by_lua 'ngx.log(ngx.ERR, "ngx.ctx.counter: ", ngx.ctx.counter)';
    }
--- request
GET /lua
--- response_body
3
--- error_log
ngx.ctx.counter: 3
lua release ngx.ctx



=== TEST 5: ngx.ctx available in log_by_lua (not defined yet)
--- config
    location /lua {
        echo hello;
        log_by_lua '
            ngx.log(ngx.ERR, "ngx.ctx.counter: ", ngx.ctx.counter)
            ngx.ctx.counter = "hello world"
        ';
    }
--- request
GET /lua
--- response_body
hello
--- error_log
ngx.ctx.counter: nil
lua release ngx.ctx



=== TEST 6: log_by_lua + shared dict
--- http_config
    lua_shared_dict foo 100k;
--- config
    location /lua {
        echo hello;
        log_by_lua '
            local foo = ngx.shared.foo
            local key = ngx.var.uri .. ngx.status
            local newval, err = foo:incr(key, 1)
            if not newval then
                if err == "not found" then
                    foo:add(key, 0)
                    newval, err = foo:incr(key, 1)
                    if not newval then
                        ngx.log(ngx.ERR, "failed to incr ", key, ": ", err)
                        return
                    end
                else
                    ngx.log(ngx.ERR, "failed to incr ", key, ": ", err)
                    return
                end
            end
            print(key, ": ", foo:get(key))
        ';
    }
--- request
GET /lua
--- response_body
hello
--- error_log eval
qr{/lua200: [12]}
--- no_error_log
[error]



=== TEST 7: ngx.ctx used in different locations and different ctx (1)
--- config
    location /t {
        echo hello;
        log_by_lua '
            ngx.log(ngx.ERR, "ngx.ctx.counter: ", ngx.ctx.counter)
        ';
    }

    location /t2 {
        content_by_lua '
            ngx.ctx.counter = 32
            ngx.say("hello")
        ';
    }
--- request
GET /t
--- response_body
hello
--- error_log
ngx.ctx.counter: nil
lua release ngx.ctx



=== TEST 8: ngx.ctx used in different locations and different ctx (2)
--- config
    location /t {
        echo hello;
        log_by_lua '
            ngx.log(ngx.ERR, "ngx.ctx.counter: ", ngx.ctx.counter)
        ';
    }

    location /t2 {
        content_by_lua '
            ngx.ctx.counter = 32
            ngx.say(ngx.ctx.counter)
        ';
    }
--- request
GET /t2
--- response_body
32
--- error_log
lua release ngx.ctx



=== TEST 9: lua error (string)
--- config
    location /lua {
        log_by_lua 'error("Bad")';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log eval
qr/failed to run log_by_lua\*: log_by_lua\(nginx\.conf:\d+\):1: Bad/



=== TEST 10: lua error (nil)
--- config
    location /lua {
        log_by_lua 'error(nil)';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
failed to run log_by_lua*: unknown reason



=== TEST 11: globals sharing
--- config
    location /lua {
        echo ok;
        log_by_lua '
            if not foo then
                foo = 1
            else
                ngx.log(ngx.INFO, "old foo: ", foo)
                foo = foo + 1
            end
            ngx.log(ngx.WARN, "foo = ", foo)
        ';
    }
--- request
GET /lua
--- response_body
ok
--- grep_error_log eval: qr/old foo: \d+/
--- grep_error_log_out eval
["", "old foo: 1\n"]



=== TEST 12: no ngx.print
--- config
    location /lua {
        log_by_lua "ngx.print(32) return 1";
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 13: no ngx.say
--- config
    location /lua {
        log_by_lua "ngx.say(32) return 1";
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 14: no ngx.flush
--- config
    location /lua {
        log_by_lua "ngx.flush()";
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 15: no ngx.eof
--- config
    location /lua {
        log_by_lua "ngx.eof()";
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 16: no ngx.send_headers
--- config
    location /lua {
        log_by_lua "ngx.send_headers()";
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 17: no ngx.location.capture
--- config
    location /lua {
        log_by_lua 'ngx.location.capture("/sub")';
        echo ok;
    }

    location /sub {
        echo sub;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 18: no ngx.location.capture_multi
--- config
    location /lua {
        log_by_lua 'ngx.location.capture_multi{{"/sub"}}';
        echo ok;
    }

    location /sub {
        echo sub;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 19: no ngx.exit
--- config
    location /lua {
        log_by_lua 'ngx.exit(0)';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 20: no ngx.redirect
--- config
    location /lua {
        log_by_lua 'ngx.redirect("/blah")';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 21: no ngx.exec
--- config
    location /lua {
        log_by_lua 'ngx.exec("/blah")';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 22: no ngx.req.set_uri(uri, true)
--- config
    location /lua {
        log_by_lua 'ngx.req.set_uri("/blah", true)';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 23: ngx.req.set_uri(uri) exists
--- config
    location /lua {
        log_by_lua 'ngx.req.set_uri("/blah") print("log_by_lua: uri: ", ngx.var.uri)';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
log_by_lua: uri: /blah



=== TEST 24: no ngx.req.read_body()
--- config
    location /lua {
        log_by_lua 'ngx.req.read_body()';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 25: no ngx.req.socket()
--- config
    location /lua {
        log_by_lua 'return ngx.req.socket()';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 26: no ngx.socket.tcp()
--- config
    location /lua {
        log_by_lua 'return ngx.socket.tcp()';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 27: no ngx.socket.connect()
--- config
    location /lua {
        log_by_lua 'return ngx.socket.connect("127.0.0.1", 80)';
        echo ok;
    }
--- request
GET /lua
--- response_body
ok
--- error_log
API disabled in the context of log_by_lua*



=== TEST 28: backtrace
--- config
    location /t {
        echo ok;
        log_by_lua '
            local bar
            local function foo()
                bar()
            end

            function bar()
                error("something bad happened")
            end

            foo()
        ';
    }
--- request
    GET /t
--- response_body
ok
--- error_log
something bad happened
stack traceback:
in function 'error'
in function 'bar'
in function 'foo'



=== TEST 29: Lua file does not exist
--- config
    location /lua {
        echo ok;
        log_by_lua_file html/test2.lua;
    }
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body
ok
--- error_log eval
qr/failed to load external Lua file ".*?test2\.lua": cannot open .*? No such file or directory/



=== TEST 30: log_by_lua runs before access logging (github issue #254)
--- config
    location /lua {
        echo ok;
        access_log logs/foo.log;
        log_by_lua 'print("hello")';
    }
--- request
GET /lua
--- stap
F(ngx_http_log_handler) {
    println("log handler")
}
F(ngx_http_lua_log_handler) {
    println("lua log handler")
}
--- stap_out
lua log handler
log handler

--- response_body
ok
--- no_error_log
[error]



=== TEST 31: reading ngx.header.HEADER in log_by_lua
--- config
    location /lua {
        echo ok;
        log_by_lua 'ngx.log(ngx.WARN, "content-type: ", ngx.header.content_type)';
    }
--- request
GET /lua

--- response_body
ok
--- error_log eval
qr{log_by_lua\(nginx\.conf:\d+\):1: content-type: text/plain}

--- no_error_log
[error]
