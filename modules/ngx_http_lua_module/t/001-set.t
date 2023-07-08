# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 5);

#log_level("warn");
no_long_string();

run_tests();

__DATA__

=== TEST 1: simple set (integer)
--- config
    location /lua {
        set_by_lua $res "return 1+1";
        echo $res;
    }
--- request
GET /lua
--- response_body
2
--- no_error_log
[error]



=== TEST 2: simple set (string)
--- config
    location /lua {
        set_by_lua $res "return 'hello' .. 'world'";
        echo $res;
    }
--- request
GET /lua
--- response_body
helloworld
--- no_error_log
[error]



=== TEST 3: internal only
--- config
    location /lua {
        set_by_lua $res "local function fib(n) if n > 2 then return fib(n-1)+fib(n-2) else return 1 end end return fib(10)";
        echo $res;
    }
--- request
GET /lua
--- response_body
55
--- no_error_log
[error]



=== TEST 4: inlined script with arguments
--- config
    location /lua {
        set_by_lua $res "return ngx.arg[1] + ngx.arg[2]" $arg_a $arg_b;
        echo $res;
    }
--- request
GET /lua?a=1&b=2
--- response_body
3
--- no_error_log
[error]



=== TEST 5: fib by arg
--- config
    location /fib {
        set_by_lua $res "local function fib(n) if n > 2 then return fib(n-1)+fib(n-2) else return 1 end end return fib(tonumber(ngx.arg[1]))" $arg_n;
        echo $res;
    }
--- request
GET /fib?n=10
--- response_body
55
--- no_error_log
[error]



=== TEST 6: adder
--- config
    location = /adder {
        set_by_lua $res
            "local a = tonumber(ngx.arg[1])
             local b = tonumber(ngx.arg[2])
             return a + b" $arg_a $arg_b;

        echo $res;
    }
--- request
GET /adder?a=25&b=75
--- response_body
100
--- no_error_log
[error]



=== TEST 7: read nginx variables directly from within Lua
--- config
    location = /set-both {
        set $b 32;
        set_by_lua $a "return tonumber(ngx.var.b) + 1";

        echo "a = $a";
    }
--- request
GET /set-both
--- response_body
a = 33
--- no_error_log
[error]



=== TEST 8: set nginx variables directly from within Lua
--- config
    location = /set-both {
        set $b "";
        set_by_lua $a "ngx.var.b = 32; return 7";

        echo "a = $a";
        echo "b = $b";
    }
--- request
GET /set-both
--- response_body
a = 7
b = 32
--- no_error_log
[error]



=== TEST 9: set non-existent nginx variables
--- config
    location = /set-both {
        #set $b "";
        set_by_lua $a "ngx.var.b = 32; return 7";

        echo "a = $a";
    }
--- request
GET /set-both
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
variable "b" not found for writing; maybe it is a built-in variable that is not changeable or you forgot to use "set $b '';" in the config file to define it first



=== TEST 10: set quote sql str
--- config
    location = /set {
        set $a "";
        set_by_lua $a "return ngx.quote_sql_str(ngx.var.a)";
        echo $a;
    }
--- request
GET /set
--- response_body
''
--- no_error_log
[error]



=== TEST 11: set md5
--- config
    location = /md5 {
        set_by_lua $a 'return ngx.md5("hello")';
        echo $a;
    }
--- request
GET /md5
--- response_body
5d41402abc4b2a76b9719d911017c592
--- no_error_log
[error]



=== TEST 12: no ngx.print
--- config
    location /lua {
        set_by_lua $res "ngx.print(32) return 1";
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 13: no ngx.say
--- config
    location /lua {
        set_by_lua $res "ngx.say(32) return 1";
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 14: no ngx.flush
--- config
    location /lua {
        set_by_lua $res "ngx.flush()";
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 15: no ngx.eof
--- config
    location /lua {
        set_by_lua $res "ngx.eof()";
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 16: no ngx.send_headers
--- config
    location /lua {
        set_by_lua $res "ngx.send_headers()";
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 17: no ngx.location.capture
--- config
    location /lua {
        set_by_lua $res 'ngx.location.capture("/sub")';
        echo $res;
    }

    location /sub {
        echo sub;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 18: no ngx.location.capture_multi
--- config
    location /lua {
        set_by_lua $res 'ngx.location.capture_multi{{"/sub"}}';
        echo $res;
    }

    location /sub {
        echo sub;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 19: no ngx.exit
--- config
    location /lua {
        set_by_lua $res 'ngx.exit(0)';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 20: no ngx.redirect
--- config
    location /lua {
        set_by_lua $res 'ngx.redirect("/blah")';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 21: no ngx.exec
--- config
    location /lua {
        set_by_lua $res 'ngx.exec("/blah")';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 22: no ngx.req.set_uri(uri, true)
--- config
    location /lua {
        set_by_lua $res 'ngx.req.set_uri("/blah", true)';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 23: ngx.req.set_uri(uri) exists
--- config
    location /lua {
        set_by_lua $res 'ngx.req.set_uri("/blah") return 1';
        echo $uri;
    }
--- request
GET /lua
--- response_body
/blah
--- no_error_log
[error]



=== TEST 24: no ngx.req.read_body()
--- config
    location /lua {
        set_by_lua $res 'ngx.req.read_body()';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 25: no ngx.req.socket()
--- config
    location /lua {
        set_by_lua $res 'return ngx.req.socket()';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 26: no ngx.socket.tcp()
--- config
    location /lua {
        set_by_lua $res 'return ngx.socket.tcp()';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 27: no ngx.socket.connect()
--- config
    location /lua {
        set_by_lua $res 'return ngx.socket.connect("127.0.0.1", 80)';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
API disabled in the context of set_by_lua*



=== TEST 28: set $limit_rate (variables with set_handler)
--- config
    location /lua {
        set $limit_rate 1000;
        rewrite_by_lua '
            ngx.var.limit_rate = 180;
        ';
        echo "limit rate = $limit_rate";
    }
--- request
    GET /lua
--- response_body
limit rate = 180
--- no_error_log
[error]



=== TEST 29: set $args and read $query_string
--- config
    location /lua {
        set $args 'hello';
        rewrite_by_lua '
            ngx.var.args = "world";
        ';
        echo $query_string;
    }
--- request
    GET /lua
--- response_body
world
--- no_error_log
[error]



=== TEST 30: set $arg_xxx
--- config
    location /lua {
        rewrite_by_lua '
            ngx.var.arg_foo = "world";
        ';
        echo $arg_foo;
    }
--- request
    GET /lua?foo=3
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
variable "arg_foo" not found for writing; maybe it is a built-in variable that is not changeable or you forgot to use "set $arg_foo '';" in the config file to define it first



=== TEST 31: symbol $ in lua code of set_by_lua
--- config
    location /lua {
        set_by_lua $res 'return "$unknown"';
        echo $res;
    }
--- request
    GET /lua
--- response_body
$unknown
--- no_error_log
[error]



=== TEST 32: symbol $ in lua code of set_by_lua_file
--- config
    location /lua {
        set_by_lua_file $res html/a.lua;
        echo $res;
    }
--- user_files
>>> a.lua
return "$unknown"
--- request
    GET /lua
--- response_body
$unknown
--- no_error_log
[error]



=== TEST 33: external script files with arguments
--- config
    location /lua {
        set_by_lua_file $res html/a.lua $arg_a $arg_b;
        echo $res;
    }
--- user_files
>>> a.lua
return ngx.arg[1] + ngx.arg[2]
--- request
GET /lua?a=5&b=2
--- response_body
7
--- no_error_log
[error]



=== TEST 34: variables in set_by_lua_file's file path
--- config
    location /lua {
        set $path "html/a.lua";
        set_by_lua_file $res $path $arg_a $arg_b;
        echo $res;
    }
--- user_files
>>> a.lua
return ngx.arg[1] + ngx.arg[2]
--- request
GET /lua?a=5&b=2
--- response_body
7
--- no_error_log
[error]



=== TEST 35: lua error (string)
--- config
    location /lua {
        set_by_lua $res 'error("Bad")';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to run set_by_lua*: set_by_lua(nginx.conf:40):1: Bad



=== TEST 36: lua error (nil)
--- config
    location /lua {
        set_by_lua $res 'error(nil)';
        echo $res;
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to run set_by_lua*: unknown reason



=== TEST 37: globals are shared in all requests.
--- config
    location /lua {
        set_by_lua_block $res {
            if not foo then
                foo = 1
            else
                ngx.log(ngx.INFO, "old foo: ", foo)
                foo = foo + 1
            end
            return foo
        }
        echo $res;
    }
--- request
GET /lua
--- response_body_like chomp
\A[12]
\z
--- no_error_log
[error]
--- grep_error_log eval: qr/(old foo: \d+|writing a global Lua variable \('\w+'\))/
--- grep_error_log_out eval
["writing a global Lua variable \('foo'\)\n", "old foo: 1\n"]



=== TEST 38: user modules using ngx.arg
--- http_config
    lua_package_path "$prefix/html/?.lua;;";
--- config
    location /lua {
        set_by_lua $res 'local foo = require "foo" return foo.go()' $arg_a $arg_b;
        echo $res;
    }
--- user_files
>>> foo.lua
module("foo", package.seeall)

function go()
    return ngx.arg[1] + ngx.arg[2]
end
--- request
GET /lua?a=1&b=2
--- response_body
3
--- no_error_log
[error]



=== TEST 39: server scope (inline)
--- config
    location /lua {
        set $a "[$res]";
        echo $a;
    }
    set_by_lua $res "return 1+1";
--- request
GET /lua
--- response_body
[2]
--- no_error_log
[error]



=== TEST 40: server if scope (inline)
--- config
    location /lua {
        set $a "[$res]";
        echo $a;
    }
    if ($arg_name = "jim") {
        set_by_lua $res "return 1+1";
    }
--- request
GET /lua?name=jim
--- response_body
[2]
--- no_error_log
[error]



=== TEST 41: location if scope (inline)
--- config
    location /lua {
        if ($arg_name = "jim") {
            set_by_lua $res "return 1+1";
            set $a "[$res]";
            echo $a;
        }
    }
--- request
GET /lua?name=jim
--- response_body
[2]
--- no_error_log
[error]



=== TEST 42: server scope (file)
--- config
    location /lua {
        set $a "[$res]";
        echo $a;
    }
    set_by_lua_file $res html/a.lua;
--- user_files
>>> a.lua
return 1+1
--- request
GET /lua
--- response_body
[2]
--- no_error_log
[error]



=== TEST 43: server if scope (file)
--- config
    location /lua {
        set $a "[$res]";
        echo $a;
    }
    if ($arg_name = "jim") {
        set_by_lua_file $res html/a.lua;
    }
--- request
GET /lua?name=jim
--- user_files
>>> a.lua
return 1+1
--- response_body
[2]
--- no_error_log
[error]



=== TEST 44: location if scope (file)
--- config
    location /lua {
        if ($arg_name = "jim") {
            set_by_lua_file $res html/a.lua;
            set $a "[$res]";
            echo $a;
        }
    }
--- user_files
>>> a.lua
return 1+1
--- request
GET /lua?name=jim
--- response_body
[2]
--- no_error_log
[error]



=== TEST 45: backtrace
--- config
    location /t {
        set_by_lua $a '
            local bar
            local foo
            function foo()
                bar()
            end

            function bar()
                error("something bad happened")
            end

            foo()
        ';
        echo ok;
    }
--- request
    GET /t
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
something bad happened
stack traceback:
in function 'error'
in function 'bar'
in function 'foo'



=== TEST 46: Lua file does not exist
--- config
    location /lua {
        set_by_lua_file $a html/test2.lua;
    }
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/failed to load external Lua file ".*?test2\.lua": cannot open .*? No such file or directory/
