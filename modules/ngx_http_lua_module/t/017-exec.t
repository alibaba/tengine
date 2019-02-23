# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 8);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
#no_shuffle();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi");
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body
Hello



=== TEST 2: empty uri arg
--- config
    location /read {
        content_by_lua '
            ngx.exec("");
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: no arg
--- config
    location /read {
        content_by_lua '
            ngx.exec();
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: too many args
--- config
    location /read {
        content_by_lua '
            ngx.exec(1, 2, 3, 4);
            ngx.say("Hi");
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 5: null uri
--- config
    location /read {
        content_by_lua '
            ngx.exec(nil)
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo "Hello";
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 6: user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi", "Yichun Zhang")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello Yichun Zhang



=== TEST 7: args in uri
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi?agentzh")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello agentzh



=== TEST 8: args in uri and user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("/hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
    }
    location /hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello a=Yichun&b=Zhang



=== TEST 9: args in uri and user args
--- config
    location /read {
        content_by_lua '
            ngx.exec("@hi?a=Yichun", "b=Zhang")
            ngx.say("Hi")
        ';
    }
    location @hi {
        echo Hello $query_string;
    }
--- request
GET /read
--- response_body
Hello 



=== TEST 10: exec after location capture (simple echo)
--- config
    location /test {
        content_by_lua_file 'html/test.lua';
    }

    location /a {
        echo "hello";
    }

    location /b {
        echo "hello";
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('/b')
--- request
    GET /test
--- response_body
hello



=== TEST 11: exec after location capture (memc)
--- config
    location /test {
        content_by_lua_file 'html/test.lua';
    }

    location /a {
        set $memc_key 'hello world';
        set $memc_value 'hello hello hello world world world';
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /b {
        set $memc_key 'hello world';
        set $memc_cmd get;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('/b')
--- request
    GET /test
--- response_body: hello hello hello world world world



=== TEST 12: exec after named location capture (simple echo)
--- config
    location /test {
        content_by_lua_file 'html/test.lua';
    }

    location /a {
        echo "hello";
    }

    location @b {
        echo "hello";
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('@b')
--- request
    GET /test
--- response_body
hello



=== TEST 13: exec after named location capture (memc)
--- config
    location /test {
        content_by_lua_file 'html/test.lua';
    }

    location /a {
        set $memc_key 'hello world';
        set $memc_value 'hello hello hello world world world';
        set $memc_cmd set;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location @b {
        set $memc_key 'hello world';
        set $memc_cmd get;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

--- user_files
>>> test.lua
ngx.location.capture('/a')

ngx.exec('@b')
--- request
    GET /test
--- response_body: hello hello hello world world world



=== TEST 14: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location (content)
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
        #echo hello;
    }
    location /p{
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location /lua {
        content_by_lua '
            ngx.exec("/p")
        ';
    }
--- request
    GET /lua
--- response_body
hello



=== TEST 15: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location (content + named location)
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
        #echo hello;
    }
    location @p {
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location /lua {
        content_by_lua '
            ngx.exec("@p")
        ';
    }
--- request
    GET /lua
--- response_body
hello



=== TEST 16: github issue #40: 2 Subrequest calls when using access_by_lua, ngx.exec and echo_location (content + post subrequest)
--- config
    location = /hi {
        echo hello;
    }
    location /sub {
        proxy_pass http://127.0.0.1:$server_port/hi;
        #echo hello;
    }
    location /p{
        #content_by_lua '
            #local res = ngx.location.capture("/sub")
            #ngx.print(res.body)
        #';
        echo_location /sub;
    }
    location blah {
        echo blah;
    }
    location /lua {
        content_by_lua '
            ngx.location.capture("/blah")
            ngx.exec("/p")
        ';
    }
--- request
    GET /lua
--- response_body
hello



=== TEST 17: pcall safe
--- config
    location /lua {
        content_by_lua '
            local function f ()
                ngx.exec("/hi")
            end

            pcall(f)
            ngx.say("hello")
        ';
    }
    location /hi {
        echo hi;
    }
--- request
GET /lua
--- error_code: 200
--- response_body
hi



=== TEST 18: lua table as "args" parameter
--- config
    location /lua {
        content_by_lua '
            local args = { foo = 3, bar = 4 }
            ngx.exec("/hi", args)
        ';
    }
    location /hi {
        echo "foo = $arg_foo";
        echo "bar = $arg_bar";
    }
--- request
GET /lua
--- error_code: 200
--- response_body
foo = 3
bar = 4



=== TEST 19: jump to internal locations requires ctx cleared
--- config
    location @proxy {
        rewrite_by_lua return;
        echo hello;
    }
    location /main {
        content_by_lua '
            ngx.exec("@proxy")
        ';
    }
--- request
    GET /main
--- response_body
hello



=== TEST 20: exec + rewrite + named locations
--- config
    location @proxy {
        rewrite_by_lua return;
        echo hello;
    }
    location /main {
        rewrite_by_lua '
            ngx.exec("@proxy")
        ';
    }
--- request
    GET /main
--- response_body
hello



=== TEST 21: exec(named location) in subrequests
--- config
    location /entry {
        echo_location /foo;
        echo_location /foo2;
    }
  location /foo {
      content_by_lua '
          ngx.exec("@bar")
      ';
  }
  location /foo2 {
      content_by_lua '
          ngx.exec("@bar")
      ';
  }

  location @bar {
      proxy_pass http://127.0.0.1:$server_port/bar;
  }
  location /bar {
      echo hello;
  }
--- request
    GET /entry
--- response_body
hello
hello



=== TEST 22: exec(normal location) in subrequests
--- config
    location /entry {
        echo_location /foo;
        echo_location /foo2;
    }
  location /foo {
      content_by_lua '
          ngx.exec("/baz")
      ';
  }
  location /foo2 {
      content_by_lua '
          ngx.exec("/baz")
      ';
  }

  location /baz {
      proxy_pass http://127.0.0.1:$server_port/bar;
  }
  location /bar {
      echo hello;
  }
--- request
    GET /entry
--- response_body
hello
hello



=== TEST 23: content_by_lua + ngx.exec + subrequest capture
--- config
    location /main {
        rewrite_by_lua '
            local res = ngx.location.capture("/test_loc");
            ngx.print("hello, ", res.body)
        ';
        content_by_lua return;
    }
    location /test_loc {
        content_by_lua '
            ngx.exec("@proxy")
        ';
    }
    location @proxy {
        #echo proxy;
        proxy_pass http://127.0.0.1:$server_port/foo;
    }
    location /foo {
        #echo_status 201;
        echo bah;
    }
--- request
    GET /main
--- response_body
hello, bah



=== TEST 24: jump to an internal location
--- config
    location /t {
        content_by_lua '
            return ngx.exec("/proxy", ngx.var.args)
        ';
    }

    location /proxy {
        internal;

        proxy_pass http://127.0.0.1:$server_port/dummy;
    }

    location = /dummy {
        echo -n dummy;
    }
--- pipelined_requests eval
["GET /t", "GET /t?foo"]
--- response_body eval
["dummy", "dummy"]
--- no_error_log
[error]



=== TEST 25: pipelined requests
--- config
    location /t {
        content_by_lua_block {
            ngx.exec("@foo")
        }
    }

    location @foo {
        return 200;
    }
--- pipelined_requests eval
["GET /t", "GET /t"]
--- error_code eval
[200, 200]
--- response_body eval
["", ""]
--- no_error_log
[error]
