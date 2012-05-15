# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#master_on();
workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 8);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: DELETE
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
DELETE



=== TEST 2: DELETE (proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
DELETE



=== TEST 3: POST (nobody, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
POST



=== TEST 4: HEAD
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_HEAD });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
HEAD



=== TEST 5: explicit GET
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_GET });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 6: implicit GET
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo")

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 7: implicit GET (empty option table)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo", {})

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET



=== TEST 8: PUT (nobody, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo_read_request_body;

        echo $echo_request_method;
        echo_request_body;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello



=== TEST 9: PUT (nobody, no proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        #echo_read_request_body;

        echo $echo_request_method;
        #echo $echo_request_body;
        echo_request_body;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello



=== TEST 10: PUT (nobody, no proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        #echo_read_request_body;

        echo $echo_request_method;
        #echo $echo_request_body;
        echo_request_body;
        #echo "[$http_content_length]";
        echo;
    }

    location /foo {
        echo $echo_request_method;
        echo -n "[$http_content_length]";
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)

            res = ngx.location.capture("/foo")
            ngx.say(res.body)

        ';
    }
--- request
GET /lua
--- response_body
PUT
hello
GET
[]



=== TEST 11: POST (with body, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo_read_request_body;

        echo $echo_request_method;
        echo_request_body;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
POST
hello



=== TEST 12: POST (with body, memc method)
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc {
        set $memc_key $echo_request_uri;
        set $memc_exptime 600;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /lua {
        content_by_lua '
            ngx.location.capture("/flush");

            res = ngx.location.capture("/memc");
            ngx.say("GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello" });
            ngx.say("PUT: " .. res.status);

            res = ngx.location.capture("/memc");
            ngx.say("cached: " .. res.body);

        ';
    }
--- request
GET /lua
--- response_body
GET: 404
PUT: 201
cached: hello



=== TEST 13: POST (with body, memc method)
--- config
    location /flush {
        set $memc_cmd flush_all;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /memc {
        set $memc_cmd "";
        set $memc_key $echo_request_uri;
        set $memc_exptime 600;
        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /lua {
        content_by_lua '
            ngx.location.capture("/flush",
                { share_all_vars = true });

            res = ngx.location.capture("/memc",
                { share_all_vars = true });
            ngx.say("GET: " .. res.status);

            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello", share_all_vars = true });
            ngx.say("PUT: " .. res.status);

            res = ngx.location.capture("/memc", { share_all_vars = true });
            ngx.say("cached: " .. res.body);
        ';
    }
--- request
GET /lua
--- response_body
GET: 404
PUT: 201
cached: hello



=== TEST 14: emtpy args option table
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = {} })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body eval: "\n"



=== TEST 15: non-empty args option table (1 pair)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
fo%3d=%3d%3e



=== TEST 16: non-empty args option table (2 pairs)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>",
                    ["="] = ":" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^(?:fo%3d=%3d%3e\&%3d=%3a|%3d=%3a\&fo%3d=%3d%3e)$



=== TEST 17: non-empty args option table (2 pairs, no special chars)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = { foo = 3,
                    bar = "hello" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^(?:bar=hello\&foo=3|foo=3\&bar=hello)$



=== TEST 18: non-empty args option table (number key)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = { [57] = "hi" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 19: non-empty args option table (plain arrays)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { args = { "hi" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 20: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo?a=3",
                { args = { b = 4 } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
a=3&b=4



=== TEST 21: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo?a=3",
                { args = "b=4" })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
a=3&b=4



=== TEST 22: is_subrequest in main request
--- config
    location /lua {
        content_by_lua '
            if ngx.is_subrequest then
                ngx.say("sub req")
            else
                ngx.say("main req")
            end
        ';
    }
--- request
    GET /lua
--- response_body
main req



=== TEST 23: is_subrequest in sub request
--- config
    location /main {
        echo_location /lua;
    }

    location /lua {
        content_by_lua '
            if ngx.is_subrequest then
                ngx.say("sub req")
            else
                ngx.say("main req")
            end
        ';
    }
--- request
    GET /main
--- response_body
sub req



=== TEST 24: is_subrequest in sub request in set_by_lua
--- config
    location /main {
        echo_location /lua;
    }

    location /lua {
        set_by_lua $a '
            if ngx.is_subrequest then
                return "sub req"
            else
                return "main req"
            end
        ';
        echo $a;
    }
--- request
    GET /main
--- response_body
sub req



=== TEST 25: header inheritance bug (without body) (github issue 38)
https://github.com/chaoslawful/lua-nginx-module/issues/38
--- config
    location /other {
        default_type 'foo/bar';
        echo -n $http_foo;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_GET });
            ngx.say("header foo: [", res.body, "]")
        ';
    }
--- request
GET /lua
--- more_headers
Foo: bar
--- response_body
header foo: [bar]



=== TEST 26: header inheritance bug (with body) (github issue 38)
https://github.com/chaoslawful/lua-nginx-module/issues/38
--- config
    location /other {
        default_type 'foo/bar';
        echo -n $http_foo;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { body = "abc" });
            ngx.say("header foo: [", res.body, "]")
        ';
    }
--- request
GET /lua
--- more_headers
Foo: bar
--- response_body
header foo: [bar]



=== TEST 27: lua calls lua via subrequests
--- config
    location /a {
        content_by_lua '
            ngx.say("hello, a");
        ';
    }
    location /b {
        content_by_lua '
            ngx.say("hello, b");
        ';
    }
    location /c {
        content_by_lua '
            ngx.say("hello, c");
        ';
    }
    location /main {
        content_by_lua '
            res1, res2 = ngx.location.capture_multi({{"/a"}, {"/b"}})
            res3 = ngx.location.capture("/c")
            ngx.print(res1.body, res2.body, res3.body)
        ';
    }
--- request
    GET /main
--- response_body
hello, a
hello, b
hello, c
--- error_log
lua reuse free buf memory



=== TEST 28: POST (with body, proxy method, main request is a POST too)
--- config
    location /other {
        default_type 'foo/bar';
        echo_read_request_body;

        echo $echo_request_method;
        echo_request_body;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
POST /lua
hi
--- response_body chomp
POST
hello



=== TEST 29: Last-Modified response header for static file subrequest
--- config
    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo.html")

            ngx.say(res.status)
            ngx.say(res.header["Last-Modified"])
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- user_files
>>> foo.html
hello, static file
--- response_body_like chomp
^200
[A-Za-z]+, \d{1,2} [A-Za-z]+ \d{4} \d{2}:\d{2}:\d{2} GMT
hello, static file$



=== TEST 30: custom ctx table for subrequest
--- config
    location /sub {
        content_by_lua '
            ngx.ctx.foo = "bar";
        ';
    }
    location /lua {
        content_by_lua '
            local ctx = {}
            res = ngx.location.capture("/sub", { ctx = ctx })

            ngx.say(ctx.foo);
            ngx.say(ngx.ctx.foo);
        ';
    }
--- request
GET /lua
--- response_body
bar
nil



=== TEST 31: share the ctx with the parent
--- config
    location /sub {
        content_by_lua '
            ngx.ctx.foo = "bar";
        ';
    }
    location /lua {
        content_by_lua '
            res = ngx.location.capture("/sub", { ctx = ngx.ctx })
            ngx.say(ngx.ctx.foo);
        ';
    }
--- request
GET /lua
--- response_body
bar



=== TEST 32: test memcached with subrequests
--- http_config
    upstream memc {
        server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        keepalive 100 single;
    }
--- config
    location /memc {
        set $memc_key some_key;
        set $memc_exptime 600;
        memc_pass memc;
    }

    location /t {
        content_by_lua '
            res = ngx.location.capture("/memc",
                { method = ngx.HTTP_PUT, body = "hello 1234" });
            -- ngx.say("PUT: " .. res.status);

            res = ngx.location.capture("/memc");
            ngx.say("some_key: " .. res.body);
        ';
    }
--- request
GET /t
--- response_body
some_key: hello 1234
--- error_log
lua reuse free buf chain, but reallocate memory because
--- no_error_log
[error]



=== TEST 33: main POST, sub GET (main does not read the body)
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_method)
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
        #proxy_pass http://127.0.0.1:8892/other;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_GET });

            ngx.print(res.body)
        ';
    }
--- request
POST /lua
hello, world
--- response_body
GET
nil
--- no_error_log
[error]



=== TEST 34: main POST, sub GET (main has read the body)
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_method)
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
        #proxy_pass http://127.0.0.1:8892/other;
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()

            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_GET });

            ngx.print(res.body)
        ';
    }
--- request
POST /lua
hello, world
--- response_body
GET
nil
--- no_error_log
[error]



=== TEST 35: main POST, sub POST (inherit bodies directly)
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_method)
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
        #proxy_pass http://127.0.0.1:8892/other;
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()

            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST });

            ngx.print(res.body)
        ';
    }
--- request
POST /lua
hello, world
--- response_body
POST
hello, world
--- no_error_log
[error]



=== TEST 36: main POST, sub PUT (inherit bodies directly)
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_method)
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
        #proxy_pass http://127.0.0.1:8892/other;
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()

            res = ngx.location.capture("/foo",
                { method = ngx.HTTP_PUT });

            ngx.print(res.body)
        ';
    }
--- request
POST /lua
hello, world
--- response_body
PUT
hello, world
--- no_error_log
[error]



=== TEST 37: recursive calls
--- config
    location /t {
        content_by_lua '
            ngx.location.capture("/t")
        ';
    }
--- request
    GET /t
--- ignore_response
--- error_log
subrequests cycle while processing "/t"



=== TEST 38: OPTIONS
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_OPTIONS });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
OPTIONS
--- no_error_log
[error]



=== TEST 39: OPTIONS with a body
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
        echo_request_body;
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_OPTIONS, body = "hello world" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chop
OPTIONS
hello world
--- no_error_log
[error]

