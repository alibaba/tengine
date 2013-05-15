# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_type = "text/my-plain";
            ngx.say("Hi");
        ';
    }
--- request
GET /read
--- response_headers
Content-Type: text/my-plain
--- response_body
Hi



=== TEST 2: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = "text/my-plain";
            ngx.say("Hi");
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- response_headers
Content-Type: text/html
--- error_code: 500



=== TEST 3: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = 3
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
Content-Length: 3
--- response_body chop
Hel



=== TEST 4: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.status = 302;
            ngx.header["Location"] = "http://agentzh.org/foo";
        ';
    }
--- request
GET /read
--- response_headers
Location: http://agentzh.org/foo
--- response_body
--- error_code: 302



=== TEST 5: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_length = 3
            ngx.header.content_length = nil
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!Content-Length
--- response_body
Hello



=== TEST 6: set multi response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- raw_response_headers_like chomp
X-Foo: a\r\n.*?X-Foo: bc\r\n
--- response_body
Hello



=== TEST 7: set response content-type header
--- config
    location /read {
        content_by_lua '
            ngx.header.content_type = {"a", "bc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
Content-Type: bc
--- response_body
Hello



=== TEST 8: set multi response content-type header and clears it
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = {}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!X-Foo
--- response_body
Hello



=== TEST 9: set multi response content-type header and clears it
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = nil
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- response_headers
!X-Foo
--- response_body
Hello



=== TEST 10: set multi response content-type header (multiple times)
--- config
    location /read {
        content_by_lua '
            ngx.header["X-Foo"] = {"a", "bc"}
            ngx.header["X-Foo"] = {"a", "abc"}
            ngx.say("Hello")
        ';
    }
--- request
GET /read
--- raw_response_headers_like chomp
X-Foo: a\r\n.*?X-Foo: abc\r\n
--- response_body
Hello



=== TEST 11: clear first, then add
--- config
    location /lua {
        content_by_lua '
            ngx.header["Foo"] = {}
            ngx.header["Foo"] = {"a", "b"}
            ngx.send_headers()
        ';
    }
--- request
    GET /lua
--- raw_response_headers_like eval
".*Foo: a\r
Foo: b.*"
--- response_body



=== TEST 12: first add, then clear, then add again
--- config
    location /lua {
        content_by_lua '
            ngx.header["Foo"] = {"c", "d"}
            ngx.header["Foo"] = {}
            ngx.header["Foo"] = {"a", "b"}
            ngx.send_headers()
        ';
    }
--- request
    GET /lua
--- raw_response_headers_like eval
".*Foo: a\r
Foo: b.*"
--- response_body



=== TEST 13: names are the same in the beginning (one value per key)
--- config
    location /lua {
        content_by_lua '
            ngx.header["Foox"] = "barx"
            ngx.header["Fooy"] = "bary"
            ngx.send_headers()
        ';
    }
--- request
    GET /lua
--- response_headers
Foox: barx
Fooy: bary



=== TEST 14: names are the same in the beginning (multiple values per key)
--- config
    location /lua {
        content_by_lua '
            ngx.header["Foox"] = {"conx1", "conx2" }
            ngx.header["Fooy"] = {"cony1", "cony2" }
            ngx.send_headers()
        ';
    }
--- request
    GET /lua
--- response_headers
Foox: conx1, conx2
Fooy: cony1, cony2



=== TEST 15: set header after ngx.print
--- config
    location /lua {
        default_type "text/plain";
        content_by_lua '
            ngx.print("hello")
            ngx.header.content_type = "text/foo"
        ';
    }
--- request
    GET /lua
--- response_body chop
hello
--- error_log
attempt to set ngx.header.HEADER after sending out response headers
--- no_error_log eval
["alert", "warn"]



=== TEST 16: get content-type header after ngx.print
--- config
    location /lua {
        default_type "text/my-plain";
        content_by_lua '
            ngx.print("hello, ")
            ngx.say(ngx.header.content_type)
        ';
    }
--- request
    GET /lua
--- response_headers
Content-Type: text/my-plain
--- response_body
hello, text/my-plain



=== TEST 17: get content-length header
--- config
    location /lua {
        content_by_lua '
            ngx.header.content_length = 2;
            ngx.say(ngx.header.content_length);
        ';
    }
--- request
    GET /lua
--- response_headers
Content-Length: 2
--- response_body
2



=== TEST 18: get content-length header
--- config
    location /lua {
        content_by_lua '
            ngx.header.foo = "bar";
            ngx.say(ngx.header.foo);
        ';
    }
--- request
    GET /lua
--- response_headers
foo: bar
--- response_body
bar



=== TEST 19: get content-length header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.var.footer = ngx.header.content_length
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua 'ngx.print("Hello")';
    }
--- request
    GET /main
--- response_headers
!Content-Length
--- response_body
Hello5



=== TEST 20: set and get content-length header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.header.content_length = 27
            ngx.var.footer = ngx.header.content_length
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua 'ngx.print("Hello")';
    }
--- request
    GET /main
--- response_headers
!Content-Length
--- response_body
Hello27



=== TEST 21: get content-type header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.var.footer = ngx.header.content_type
        ';
        echo_after_body $footer;
    }
    location /echo {
        default_type 'abc/foo';
        content_by_lua 'ngx.print("Hello")';
    }
--- request
    GET /main
--- response_headers
Content-Type: abc/foo
--- response_body
Helloabc/foo



=== TEST 22: set and get content-type header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.header.content_type = "text/blah"
            ngx.var.footer = ngx.header.content_type
        ';
        echo_after_body $footer;
    }
    location /echo {
        default_type 'abc/foo';
        content_by_lua 'ngx.print("Hello")';
    }
--- request
    GET /main
--- response_headers
Content-Type: text/blah
--- response_body
Hellotext/blah



=== TEST 23: get user header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.var.footer = ngx.header.baz
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua '
            ngx.header.baz = "bah"
            ngx.print("Hello")
        ';
    }
--- request
    GET /main
--- response_headers
baz: bah
--- response_body
Hellobah



=== TEST 24: set and get user header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.header.baz = "foo"
            ngx.var.footer = ngx.header.baz
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua '
            ngx.header.baz = "bah"
            ngx.print("Hello")
        ';
    }
--- request
    GET /main
--- response_headers
baz: foo
--- response_body
Hellofoo



=== TEST 25: get multiple user header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.var.footer = table.concat(ngx.header.baz, ", ")
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua '
            ngx.header.baz = {"bah", "blah"}
            ngx.print("Hello")
        ';
    }
--- request
    GET /main
--- raw_response_headers_like eval
"baz: bah\r
.*?baz: blah"
--- response_body
Hellobah, blah



=== TEST 26: set and get multiple user header (proxy)
--- config
    location /main {
        set $footer '';
        proxy_pass http://127.0.0.1:$server_port/echo;
        header_filter_by_lua '
            ngx.header.baz = {"foo", "baz"}
            ngx.var.footer = table.concat(ngx.header.baz, ", ")
        ';
        echo_after_body $footer;
    }
    location /echo {
        content_by_lua '
            ngx.header.baz = {"bah", "hah"}
            ngx.print("Hello")
        ';
    }
--- request
    GET /main
--- raw_response_headers_like eval
"baz: foo\r
.*?baz: baz"
--- response_body
Hellofoo, baz



=== TEST 27: get non-existant header
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.header.foo);
        ';
    }
--- request
    GET /lua
--- response_headers
!foo
--- response_body
nil



=== TEST 28: get non-existant header
--- config
    location /lua {
        content_by_lua '
            ngx.header.foo = {"bah", "baz", "blah"}
            ngx.header.foo = nil
            ngx.say(ngx.header.foo);
        ';
    }
--- request
    GET /lua
--- response_headers
!foo
--- response_body
nil



=== TEST 29: override domains in the cookie
--- config
    location /foo {
        echo hello;
        add_header Set-Cookie 'foo=bar; Domain=backend.int';
        add_header Set-Cookie 'baz=bah; Domain=backend.int';
    }

    location /main {
        proxy_pass http://127.0.0.1:$server_port/foo;
        header_filter_by_lua '
            local cookies = ngx.header.set_cookie
            if not cookies then return end
            if type(cookies) ~= "table" then cookies = {cookies} end
            local newcookies = {}
            for i, val in ipairs(cookies) do
                local newval = string.gsub(val, "([dD]omain)=[%w_-\\\\.]+",
                          "%1=external.domain.com")
                table.insert(newcookies, newval)
            end
            ngx.header.set_cookie = newcookies
        ';
    }
--- request
    GET /main
--- response_headers
Set-Cookie: foo=bar; Domain=external.domain.com, baz=bah; Domain=external.domain.com
--- response_body
hello



=== TEST 30: set single value to cache-control
--- config
    location /lua {
        content_by_lua '
            ngx.header.cache_control = "private"
            ngx.say("Cache-Control: ", ngx.var.sent_http_cache_control)
        ';
    }
--- request
    GET /lua
--- response_headers
Cache-Control: private
--- response_body
Cache-Control: private



=== TEST 31: set multi values to cache-control
--- config
    location /lua {
        content_by_lua '
            ngx.header.cache_control = { "private", "no-store" }
            ngx.say("Cache-Control: ", ngx.var.sent_http_cache_control)
        ';
    }
--- request
    GET /lua
--- response_headers
Cache-Control: private, no-store
--- response_body
Cache-Control: private; no-store



=== TEST 32: set multi values to cache-control and override it with a single value
--- config
    location /lua {
        content_by_lua '
            ngx.header.cache_control = { "private", "no-store" }
            ngx.header.cache_control = { "no-cache" }
            ngx.say("Cache-Control: ", ngx.var.sent_http_cache_control)
            ngx.say("Cache-Control: ", ngx.header.cache_control)
        ';
    }
--- request
    GET /lua
--- response_headers
Cache-Control: no-cache
--- response_body
Cache-Control: no-cache
Cache-Control: no-cache



=== TEST 33: set multi values to cache-control and override it with multiple values
--- config
    location /lua {
        content_by_lua '
            ngx.header.cache_control = { "private", "no-store" }
            ngx.header.cache_control = { "no-cache", "blah", "foo" }
            ngx.say("Cache-Control: ", ngx.var.sent_http_cache_control)
            ngx.say("Cache-Control: ", table.concat(ngx.header.cache_control, "; "))
        ';
    }
--- request
    GET /lua
--- response_headers
Cache-Control: no-cache, blah, foo
--- response_body
Cache-Control: no-cache; blah; foo
Cache-Control: no-cache; blah; foo



=== TEST 34: set the www-authenticate response header
--- config
    location /lua {
        content_by_lua '
            ngx.header.www_authenticate = "blah"
            ngx.say("WWW-Authenticate: ", ngx.var.sent_http_www_authenticate)
        ';
    }
--- request
    GET /lua
--- response_headers
WWW-Authenticate: blah
--- response_body
WWW-Authenticate: blah



=== TEST 35: set and clear the www-authenticate response header
--- config
    location /lua {
        content_by_lua '
            ngx.header.foo = "blah"
            ngx.header.foo = nil
            ngx.say("Foo: ", ngx.var.sent_http_foo)
        ';
    }
--- request
    GET /lua
--- response_headers
!Foo
--- response_body
Foo: nil



=== TEST 36: set multi values to cache-control and override it with multiple values (to reproduce a bug)
--- config
    location /lua {
        content_by_lua '
            ngx.header.cache_control = { "private", "no-store", "foo", "bar", "baz" }
            ngx.header.cache_control = {}
            ngx.send_headers()
            ngx.say("Cache-Control: ", ngx.var.sent_http_cache_control)
        ';
        add_header Cache-Control "blah";
    }
--- request
    GET /lua
--- response_headers
Cache-Control: blah
--- response_body
Cache-Control: blah



=== TEST 37: set last-modified and return 304
--- config
  location /lua {
        content_by_lua '
            ngx.header["Last-Modified"] = ngx.http_time(1290079655)
            ngx.say(ngx.header["Last-Modified"])
        ';
    }
--- request
    GET /lua
--- more_headers
If-Modified-Since: Thu, 18 Nov 2010 11:27:35 GMT
--- response_headers
Last-Modified: Thu, 18 Nov 2010 11:27:35 GMT
--- error_code: 304



=== TEST 38: set last-modified and return 200
--- config
  location /lua {
        content_by_lua '
            ngx.header["Last-Modified"] = ngx.http_time(1290079655)
            ngx.say(ngx.header["Last-Modified"])
        ';
    }
--- request
    GET /lua
--- more_headers
If-Modified-Since: Thu, 18 Nov 2010 11:27:34 GMTT
--- response_headers
Last-Modified: Thu, 18 Nov 2010 11:27:35 GMT
--- response_body
Thu, 18 Nov 2010 11:27:35 GMT



=== TEST 39: set response content-encoding header should bypass ngx_http_gzip_filter_module
--- config
    default_type text/plain;
    gzip             on;
    gzip_min_length  1;
    gzip_types       text/plain;
    location /read {
        content_by_lua '
            ngx.header.content_encoding = "gzip";
            ngx.say("Hello, world, my dear friend!");
        ';
    }
--- request
GET /read
--- more_headers
Accept-Encoding: gzip
--- response_headers
Content-Type: text/plain
--- response_body
Hello, world, my dear friend!



=== TEST 40: no transform underscores (write)
--- config
    lua_transform_underscores_in_response_headers off;
    location = /t {
        content_by_lua '
            ngx.header.foo_bar = "Hello"
            ngx.say(ngx.header.foo_bar)
            ngx.say(ngx.header["foo-bar"])
        ';
    }
--- request
    GET /t
--- raw_response_headers_like eval
"\r\nfoo_bar: Hello\r\n"
--- response_body
Hello
nil



=== TEST 41: with transform underscores (write)
--- config
    lua_transform_underscores_in_response_headers on;
    location = /t {
        content_by_lua '
            ngx.header.foo_bar = "Hello"
            ngx.say(ngx.header.foo_bar)
            ngx.say(ngx.header["foo-bar"])
        ';
    }
--- request
    GET /t
--- raw_response_headers_like eval
"\r\nfoo-bar: Hello\r\n"
--- response_body
Hello
Hello



=== TEST 42: github issue #199: underscores in lua variables
--- config
    location /read {
        content_by_lua '
          ngx.header.content_type = "text/my-plain"

          local results = {}
          results.something = "hello"
          results.content_type = "anything"
          results.somehing_else = "hi"

          for k, v in pairs(results) do
            ngx.say(k .. ": " .. v)
          end
        ';
    }
--- request
GET /read
--- response_headers
Content-Type: text/my-plain

--- response_body
somehing_else: hi
something: hello
content_type: anything
--- no_error_log
[error]

