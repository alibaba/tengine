# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 32);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: basic print
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            local ok, err = ngx.print("Hello, Lua!\\n")
            if not ok then
                ngx.log(ngx.ERR, "print failed: ", err)
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, Lua!
--- no_error_log
[error]
--- grep_error_log eval: qr/lua caching unused lua thread|lua reusing cached lua thread/
--- grep_error_log_out eval
[
    "lua caching unused lua thread\n",
    "lua reusing cached lua thread
lua caching unused lua thread
",
]



=== TEST 2: basic say
--- config
    location /say {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            local ok, err = ngx.say("Hello, Lua!")
            if not ok then
                ngx.log(ngx.ERR, "say failed: ", err)
                return
            end
            local ok, err = ngx.say("Yay! ", 123)
            if not ok then
                ngx.log(ngx.ERR, "say failed: ", err)
                return
            end
        ';
    }
--- request
GET /say
--- response_body
Hello, Lua!
Yay! 123
--- no_error_log
[error]



=== TEST 3: no ngx.echo
--- config
    location /lua {
        content_by_lua 'ngx.echo("Hello, Lua!\\n")';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/content_by_lua\(nginx\.conf:\d+\):1: attempt to call field 'echo' \(a nil value\)/



=== TEST 4: variable
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua 'local v = ngx.var["request_uri"] ngx.print("request_uri: ", v, "\\n")';
    }
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 5: variable (file)
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
--- user_files
>>> test.lua
local v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 6: calc expression
--- config
    location /lua {
        content_by_lua_file html/calc.lua;
    }
--- user_files
>>> calc.lua
local function uri_unescape(uri)
    local function convert(hex)
        return string.char(tonumber("0x"..hex))
    end
    local s = string.gsub(uri, "%%([0-9a-fA-F][0-9a-fA-F])", convert)
    return s
end

local function eval_exp(str)
    return loadstring("return "..str)()
end

local exp_str = ngx.var["arg_exp"]
-- print("exp: '", exp_str, "'\n")
local status, res
status, res = pcall(uri_unescape, exp_str)
if not status then
    ngx.print("error: ", res, "\n")
    return
end
status, res = pcall(eval_exp, res)
if status then
    ngx.print("result: ", res, "\n")
else
    ngx.print("error: ", res, "\n")
end
--- request
GET /lua?exp=1%2B2*math.sin(3)%2Fmath.exp(4)-math.sqrt(2)
--- response_body
result: -0.4090441561579



=== TEST 7: read $arg_xxx
--- config
    location = /lua {
        content_by_lua 'local who = ngx.var.arg_who
            ngx.print("Hello, ", who, "!")';
    }
--- request
GET /lua?who=agentzh
--- response_body chomp
Hello, agentzh!



=== TEST 8: capture location
--- config
    location /other {
        echo "hello, world";
    }

    location /lua {
        content_by_lua 'local res = ngx.location.capture("/other"); ngx.print("status=", res.status, " "); ngx.print("body=", res.body)';
    }
--- request
GET /lua
--- response_body
status=200 body=hello, world



ei= TEST 9: capture non-existed location
--- config
    location /lua {
        content_by_lua 'local res = ngx.location.capture("/other"); ngx.print("status=", res.status)';
    }
--- request
GET /lua
--- response_body: status=404



=== TEST 9: invalid capture location (not as expected...)
--- config
    location /lua {
        content_by_lua 'local res = ngx.location.capture("*(#*"); ngx.say("res=", res.status)';
    }
--- request
GET /lua
--- response_body
res=404



=== TEST 10: nil is "nil"
--- config
    location /lua {
        content_by_lua 'ngx.say(nil)';
    }
--- request
GET /lua
--- response_body
nil



=== TEST 11: write boolean
--- config
    location /lua {
        content_by_lua 'ngx.say(true, " ", false)';
    }
--- request
GET /lua
--- response_body
true false



=== TEST 12: bad argument type to ngx.location.capture
--- config
    location /lua {
        content_by_lua 'ngx.location.capture(nil)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 13: capture location (default 0);
--- config
 location /recur {
       content_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               local res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body, "\\n");
           else
               ngx.print("end\\n");
           end
           ';
   }
--- request
GET /recur
--- response_body
num is: 0
end



=== TEST 14: capture location
--- config
 location /recur {
       content_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               local res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body);
           else
               ngx.print("end\\n");
           end
           ';
   }
--- request
GET /recur?num=3
--- response_body
num is: 3
status=200 body=num is: 2
status=200 body=num is: 1
status=200 body=num is: 0
end



=== TEST 15: setting nginx variables from within Lua
--- config
 location /set {
       set $a "";
       content_by_lua 'ngx.var.a = 32; ngx.say(ngx.var.a)';
       add_header Foo $a;
   }
--- request
GET /set
--- response_headers
Foo: 32
--- response_body
32



=== TEST 16: nginx quote sql string 1
--- config
 location /set {
       set $a 'hello\n\r\'"\\';
       content_by_lua 'ngx.say(ngx.quote_sql_str(ngx.var.a))';
   }
--- request
GET /set
--- response_body
'hello\n\r\'\"\\'



=== TEST 17: nginx quote sql string 2
--- config
location /set {
    set $a "hello\n\r'\"\\";
    content_by_lua 'ngx.say(ngx.quote_sql_str(ngx.var.a))';
}
--- request
GET /set
--- response_body
'hello\n\r\'\"\\'



=== TEST 18: use dollar
--- config
location /set {
    content_by_lua '
        local s = "hello 112";
        ngx.say(string.find(s, "%d+$"))';
}
--- request
GET /set
--- response_body
79



=== TEST 19: subrequests do not share variables of main requests by default
--- config
location /sub {
    echo $a;
}
location /parent {
    set $a 12;
    content_by_lua 'local res = ngx.location.capture("/sub"); ngx.print(res.body)';
}
--- request
GET /parent
--- response_body eval: "\n"



=== TEST 20: subrequests can share variables of main requests
--- config
location /sub {
    echo $a;
}
location /parent {
    set $a 12;
    content_by_lua '
        local res = ngx.location.capture(
            "/sub",
            { share_all_vars = true }
        );
        ngx.print(res.body)
    ';
}
--- request
GET /parent
--- response_body
12



=== TEST 21: main requests use subrequests' variables
--- config
location /sub {
    set $a 12;
}
location /parent {
    content_by_lua '
        local res = ngx.location.capture("/sub", { share_all_vars = true });
        ngx.say(ngx.var.a)
    ';
}
--- request
GET /parent
--- response_body
12



=== TEST 22: main requests do NOT use subrequests' variables
--- config
location /sub {
    set $a 12;
}
location /parent {
    content_by_lua '
        local res = ngx.location.capture("/sub", { share_all_vars = false });
        ngx.say(ngx.var.a)
    ';
}
--- request
GET /parent
--- response_body_like eval: "\n"



=== TEST 23: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        echo "hello, world";
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
        ';
    }
--- request
GET /lua
--- response_body
type: foo/bar



=== TEST 24: capture location multi-value headers
--- config
    location /other {
        #echo "hello, world";
        content_by_lua '
            ngx.header["Set-Cookie"] = {"a", "hello, world", "foo"}
            local ok, err = ngx.eof()
            if not ok then
                ngx.log(ngx.ERR, "eof failed: ", err)
                return
            end
        ';
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other");
            ngx.say("type: ", type(res.header["Set-Cookie"]));
            ngx.say("len: ", #res.header["Set-Cookie"]);
            ngx.say("value: ", table.concat(res.header["Set-Cookie"], "|"))
        ';
    }
--- request
GET /lua
--- response_body
type: table
len: 3
value: a|hello, world|foo
--- no_error_log
[error]



=== TEST 25: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.header.Bar = "Bah";
        ';
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
            ngx.say("Bar: ", res.header["Bar"]);
        ';
    }
--- request
GET /lua
--- response_body
type: foo/bar
Bar: Bah



=== TEST 26: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.header.Bar = "Bah";
            ngx.header.Bar = nil;
        ';
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
            ngx.say("Bar: ", res.header["Bar"] or "nil");
        ';
    }
--- request
GET /lua
--- response_body
type: foo/bar
Bar: nil



=== TEST 27: HTTP 1.0 response
--- config
    location /lua {
        content_by_lua '
            local data = "hello, world"
            -- ngx.header["Content-Length"] = #data
            -- ngx.header.content_length = #data
            ngx.print(data)
        ';
    }
    location /main {
        proxy_pass http://127.0.0.1:$server_port/lua;
    }
--- request
GET /main
--- response_headers
Content-Length: 12
--- response_body chop
hello, world
--- no_error_log
[error]
[alert]



=== TEST 28: multiple eof
--- config
    location /lua {
        content_by_lua '
            ngx.say("Hi")

            local ok, err = ngx.eof()
            if not ok then
                ngx.log(ngx.WARN, "eof failed: ", err)
                return
            end

            ok, err = ngx.eof()
            if not ok then
                ngx.log(ngx.WARN, "eof failed: ", err)
                return
            end

        ';
    }
--- request
GET /lua
--- response_body
Hi
--- no_error_log
[error]
--- error_log
eof failed: seen eof



=== TEST 29: nginx vars in script path
--- config
    location ~ ^/lua/(.+)$ {
        content_by_lua_file html/$1.lua;
    }
--- user_files
>>> calc.lua
local a,b = ngx.var.arg_a, ngx.var.arg_b
ngx.say(a+b)
--- request
GET /lua/calc?a=19&b=81
--- response_body
100



=== TEST 30: nginx vars in script path
--- config
    location ~ ^/lua/(.+)$ {
        content_by_lua_file html/$1.lua;
    }
    location /main {
        echo_location /lua/sum a=3&b=2;
        echo_location /lua/diff a=3&b=2;
    }
--- user_files
>>> sum.lua
local a,b = ngx.var.arg_a, ngx.var.arg_b
ngx.say(a+b)
>>> diff.lua
local a,b = ngx.var.arg_a, ngx.var.arg_b
ngx.say(a-b)
--- request
GET /main
--- response_body
5
1



=== TEST 31: basic print (HEAD + HTTP 1.1)
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua 'ngx.print("Hello, Lua!\\n")';
    }
--- request
HEAD /lua
--- response_body



=== TEST 32: basic print (HEAD + HTTP 1.0)
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        content_by_lua '
            ngx.print("Hello, Lua!\\n")
        ';
    }
--- request
HEAD /lua HTTP/1.0
--- response_headers
!Content-Length
--- response_body



=== TEST 33: headers_sent & HEAD
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.headers_sent)
            local ok, err = ngx.flush()
            if not ok then
                ngx.log(ngx.WARN, "failed to flush: ", err)
                return
            end
            ngx.say(ngx.headers_sent)
        ';
    }
--- request
HEAD /lua
--- response_body
--- no_error_log
[error]
--- error_log
failed to flush: header only



=== TEST 34: HEAD & ngx.say
--- config
    location /lua {
        content_by_lua '
            ngx.send_headers()
            local ok, err = ngx.say(ngx.headers_sent)
            if not ok then
                ngx.log(ngx.WARN, "failed to say: ", err)
                return
            end
        ';
    }
--- request
HEAD /lua
--- response_body
--- no_error_log
[error]
--- error_log
failed to say: header only



=== TEST 35: ngx.eof before ngx.say
--- config
    location /lua {
        content_by_lua '
            local ok, err = ngx.eof()
            if not ok then
                ngx.log(ngx.ERR, "eof failed: ", err)
                return
            end

            ok, err = ngx.say(ngx.headers_sent)
            if not ok then
                ngx.log(ngx.WARN, "failed to say: ", err)
                return
            end
        ';
    }
--- request
GET /lua
--- response_body
--- no_error_log
[error]
--- error_log
failed to say: seen eof



=== TEST 36: headers_sent + GET
--- config
    location /lua {
        content_by_lua '
            -- print("headers sent: ", ngx.headers_sent)
            ngx.say(ngx.headers_sent)
            ngx.say(ngx.headers_sent)
            -- ngx.flush()
            ngx.say(ngx.headers_sent)
        ';
    }
--- request
GET /lua
--- response_body
false
true
true



=== TEST 37: HTTP 1.0 response with Content-Length
--- config
    location /lua {
        content_by_lua '
            local data = "hello,\\nworld\\n"
            ngx.header["Content-Length"] = #data
            ngx.say("hello,")
            ngx.flush()
            -- ngx.location.capture("/sleep")
            ngx.say("world")
        ';
    }
    location /sleep {
        echo_sleep 2;
    }
    location /main {
        proxy_pass http://127.0.0.1:$server_port/lua;
    }
--- request
GET /main
--- response_headers
Content-Length: 13
--- response_body
hello,
world
--- timeout: 5
--- no_error_log
[error]
[alert]



=== TEST 38: ngx.print table arguments (github issue #54)
--- config
    location /t {
        content_by_lua 'ngx.print({10, {0, 5}, 15}, 32)';
    }
--- request
    GET /t
--- response_body chop
10051532



=== TEST 39: ngx.say table arguments (github issue #54)
--- config
    location /t {
        content_by_lua 'ngx.say({10, {0, "5"}, 15}, 32)';
    }
--- request
    GET /t
--- response_body
10051532



=== TEST 40: Lua file does not exist
--- config
    location /lua {
        content_by_lua_file html/test2.lua;
    }
--- user_files
>>> test.lua
local v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body_like: 404 Not Found
--- error_code: 404
--- error_log eval
qr/failed to load external Lua file ".*?test2\.lua": cannot open .*? No such file or directory/



=== TEST 41: .lua file with shebang
--- config
    location /lua {
        content_by_lua_file html/test.lua;
    }
--- user_files
>>> test.lua
#!/bin/lua

ngx.say("line ", debug.getinfo(1).currentline)
--- request
GET /lua?a=1&b=2
--- response_body
line 3
--- no_error_log
[error]



=== TEST 42: syntax error in inlined Lua code
--- config
    location /lua {
        content_by_lua 'for end';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/failed to load inlined Lua code: content_by_lua\(nginx.conf:40\)/



=== TEST 43: syntax error in content_by_lua_block
--- config
    location /lua {

        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/failed to load inlined Lua code: content_by_lua\(nginx.conf:41\)/



=== TEST 44: syntax error in second content_by_lua_block
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/failed to load inlined Lua code: content_by_lua\(nginx.conf:46\)/



=== TEST 45: syntax error in thrid content_by_lua_block
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log eval
qr/failed to load inlined Lua code: content_by_lua\(nginx.conf:52\)/



=== TEST 46: syntax error in included file
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    include ../html/lua.conf;
--- user_files
>>> lua.conf
    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to load inlined Lua code: content_by_lua(../html/lua.conf:2):2: unexpected symbol near ''for end''



=== TEST 47: syntax error with very long filename
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    include ../html/1234567890123456789012345678901234.conf;
--- user_files
>>> 1234567890123456789012345678901234.conf
    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to load inlined Lua code: content_by_lua(...234567890123456789012345678901234.conf:2)



=== TEST 48: syntax error in /tmp/lua.conf
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    include /tmp/lua.conf;
--- user_files
>>> /tmp/lua.conf
    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to load inlined Lua code: content_by_lua(/tmp/lua.conf:2)



=== TEST 49: syntax error in /tmp/12345678901234567890123456789012345.conf
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    include /tmp/12345678901234567890123456789012345.conf;

--- user_files
>>> /tmp/12345678901234567890123456789012345.conf
    location /lua {
        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to load inlined Lua code: content_by_lua(...345678901234567890123456789012345.conf:2)



=== TEST 50: the error line number greater than 9
--- config
    location /foo {
        content_by_lua_block {
            'for end';
        }
    }

    location /bar {
        content_by_lua_block {
            'for end';
        }
    }

    include /tmp/12345678901234567890123456789012345.conf;

--- user_files
>>> /tmp/12345678901234567890123456789012345.conf
    location /lua {












        content_by_lua_block {
            'for end';
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
failed to load inlined Lua code: content_by_lua(...45678901234567890123456789012345.conf:14)



=== TEST 51: Lua file permission denied
--- config
    location /lua {
        content_by_lua_file /etc/shadow;
    }
--- request
GET /lua
--- response_body_like: 503 Service Temporarily Unavailable
--- error_code: 503
