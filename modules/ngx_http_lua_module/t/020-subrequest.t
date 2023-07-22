# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#master_on();
#workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

no_root_location;
repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 23);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

#no_diff();
no_long_string();
#no_shuffle();

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
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
DELETE
--- error_log
lua http subrequest "/other?"
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
DELETE
--- no_error_log
[error]



=== TEST 3: POST (nobody, proxy method)
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /foo {
        proxy_pass http://127.0.0.1:$server_port/other;
    }

    location /t {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST });

            ngx.print(res.body)
        ';
    }
--- request
GET /t
--- response_body
POST
--- no_error_log
[error]



=== TEST 4: HEAD
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_HEAD });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_GET });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo")

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo", {})

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET
--- no_error_log
[error]



=== TEST 8: PUT (with body, proxy method)
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
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello
--- no_error_log
[error]



=== TEST 9: PUT (with body, no proxy method)
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
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_PUT, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
PUT
hello
--- no_error_log
[error]



=== TEST 10: PUT (no body, no proxy method)
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
            local res = ngx.location.capture("/other",
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
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo",
                { method = ngx.HTTP_POST, body = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body chomp
POST
hello
--- no_error_log
[error]



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

            local res = ngx.location.capture("/memc");
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
--- no_error_log
[error]



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

            local res = ngx.location.capture("/memc",
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
--- no_error_log
[error]



=== TEST 14: empty args option table
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = {} })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body eval: "\n"
--- no_error_log
[error]



=== TEST 15: non-empty args option table (1 pair)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
fo%3D=%3D%3E
--- no_error_log
[error]



=== TEST 16: non-empty args option table (2 pairs)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { ["fo="] = "=>",
                    ["="] = ":" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^(?:fo%3D=%3D%3E\&%3D=%3A|%3D=%3A\&fo%3D=%3D%3E)$
--- no_error_log
[error]
--- no_error_log
[error]



=== TEST 17: non-empty args option table (2 pairs, no special chars)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { foo = 3,
                    bar = "hello" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like chop
^(?:bar=hello\&foo=3|foo=3\&bar=hello)$
--- no_error_log
[error]



=== TEST 18: non-empty args option table (number key)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { [57] = "hi" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
attempt to use a non-string key in the "args" option table



=== TEST 19: non-empty args option table (plain arrays)
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo",
                { args = { "hi" } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
attempt to use a non-string key in the "args" option table



=== TEST 20: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo?a=3",
                { args = { b = 4 } })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
a=3&b=4
--- no_error_log
[error]



=== TEST 21: more args
--- config
    location /foo {
        echo $query_string;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo?a=3",
                { args = "b=4" })
            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
a=3&b=4
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



=== TEST 25: header inheritance bug (without body) (github issue 38)
https://github.com/chaoslawful/lua-nginx-module/issues/38
--- config
    location /other {
        default_type 'foo/bar';
        echo -n $http_foo;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
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
--- no_error_log
[error]



=== TEST 26: header inheritance bug (with body) (github issue 38)
https://github.com/chaoslawful/lua-nginx-module/issues/38
--- config
    location /other {
        default_type 'foo/bar';
        echo -n $http_foo;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
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
--- no_error_log
[error]



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
            local res1, res2 = ngx.location.capture_multi({{"/a"}, {"/b"}})
            local res3 = ngx.location.capture("/c")
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
--- no_error_log
[error]



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
            local res = ngx.location.capture("/foo",
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
--- no_error_log
[error]



=== TEST 29: Last-Modified response header for static file subrequest
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/foo.html")

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
--- no_error_log
[error]



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
            local res = ngx.location.capture("/sub", { ctx = ctx })

            ngx.say(ctx.foo);
            ngx.say(ngx.ctx.foo);
        ';
    }
--- request
GET /lua
--- response_body
bar
nil
--- no_error_log
[error]



=== TEST 31: share the ctx with the parent
--- config
    location /sub {
        content_by_lua '
            ngx.ctx.foo = "bar";
        ';
    }
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/sub", { ctx = ngx.ctx })
            ngx.say(ngx.ctx.foo);
        ';
    }
--- request
GET /lua
--- response_body
bar
--- no_error_log
[error]



=== TEST 32: test memcached with subrequests
--- http_config
    upstream memc {
        server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        keepalive 100;
    }
--- config
    location /memc {
        set $memc_key some_key;
        set $memc_exptime 600;
        memc_pass memc;
    }

    location /t {
        content_by_lua '
            local res = ngx.location.capture("/memc",
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
            local res = ngx.location.capture("/foo",
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

            local res = ngx.location.capture("/foo",
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

            local res = ngx.location.capture("/foo",
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

            local res = ngx.location.capture("/foo",
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
lua subrequests cycle while processing "/t"



=== TEST 38: OPTIONS
--- config
    location /other {
        default_type 'foo/bar';
        echo $echo_request_method;
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
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
            local res = ngx.location.capture("/other",
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



=== TEST 40: encode args table with a multi-value arg.
--- config
    location /t {
        content_by_lua '
            local args, err = ngx.req.get_uri_args()
            if err then
                ngx.say("err: ", err)
            end

            local res = ngx.location.capture("/sub", { args = args })
            ngx.print(res.body)
        ';
    }

    location /sub {
        echo $query_string;
    }
--- request
GET /t?r[]=http%3A%2F%2Fajax.googleapis.com%3A80%2Fajax%2Flibs%2Fjquery%2F1.7.2%2Fjquery.min.js&r[]=http%3A%2F%2Fajax.googleapis.com%3A80%2Fajax%2Flibs%2Fdojo%2F1.7.2%2Fdojo%2Fdojo.js.uncompressed.js
--- response_body
r%5B%5D=http%3A%2F%2Fajax.googleapis.com%3A80%2Fajax%2Flibs%2Fjquery%2F1.7.2%2Fjquery.min.js&r%5B%5D=http%3A%2F%2Fajax.googleapis.com%3A80%2Fajax%2Flibs%2Fdojo%2F1.7.2%2Fdojo%2Fdojo.js.uncompressed.js
--- no_error_log
[error]



=== TEST 41: subrequests finalized with NGX_ERROR
--- config
    location /sub {
        content_by_lua '
            ngx.exit(ngx.ERROR)
        ';
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        ';
    }
--- request
GET /main
--- response_body
status: 500
body: 



=== TEST 42: subrequests finalized with 500
--- config
    location /sub {
        return 500;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        ';
    }
--- request
GET /main
--- response_body
status: 500
body: 



=== TEST 43: subrequests with an output body filter returning NGX_ERROR
--- config
    location /sub {
        echo hello world;
        body_filter_by_lua '
            return ngx.ERROR
        ';
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        ';
    }
--- request
GET /main
--- stap2
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
--- response_body
--- error_code
--- no_error_log
[error]



=== TEST 44: subrequests truncated in its response body due to premature connection close (nonbuffered)
--- config
    server_tokens off;
    location /memc {
        internal;

        set $memc_key 'foo';
        #set $memc_exptime 300;
        memc_pass 127.0.0.1:19112; #$TEST_NGINX_MEMCACHED_PORT;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/memc")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19112
--- tcp_query_len: 9
--- tcp_reply eval
"VALUE foo 0 1024\r\nhello world"

--- stap2
F(ngx_http_lua_capture_body_filter) {
    if (pid() == target() && $r != $r->main) {
        printf("lua capture body output: %s\n", ngx_chain_dump($in))
        if ($in->buf->last_in_chain) {
            print_ubacktrace()
        }
    }
}

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true
--- error_log
upstream prematurely closed connection



=== TEST 45: subrequests truncated in its response body due to upstream read timeout (nonbuffered)
--- config
    memc_read_timeout 100ms;
    location /memc {
        internal;

        set $memc_key 'foo';
        #set $memc_exptime 300;
        memc_pass 127.0.0.1:19112; #$TEST_NGINX_MEMCACHED_PORT;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/memc")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19112
--- tcp_no_close
--- tcp_reply eval
"VALUE foo 0 1024\r\nhello world"

--- stap2
F(ngx_http_lua_capture_body_filter) {
    if (pid() == target() && $r != $r->main) {
        printf("lua capture body output: %s\n", ngx_chain_dump($in))
        //if ($in->buf->last_in_chain) {
            print_ubacktrace()
        //}
    }
}

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
conn err: 110: upstream timed out
upstream fin req: error=0 eof=0 rc=504
post subreq: rc=0, status=200

--- response_body_like chop
^status: 200
body: [^\n]*
truncated: true

--- error_log
upstream timed out



=== TEST 46: subrequests truncated in its response body due to premature connection close (buffered)
--- config
    server_tokens off;

    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.0 200 OK\r\nContent-Length: 1024\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true

--- error_log
upstream prematurely closed connection



=== TEST 47: subrequests truncated in its response body due to read timeout (buffered)
--- config
    location /proxy {
        internal;

        proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.0 200 OK\r\nContent-Length: 1024\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
conn err: 110: upstream timed out
upstream fin req: error=0 eof=0 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: 
truncated: true

--- error_log
upstream timed out



=== TEST 48: subrequests truncated in its response body due to premature connection close (buffered, no content-length)
--- config
    server_tokens off;
    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.0 200 OK\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=0
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: false

--- no_error_log
[error]



=== TEST 49: subrequests truncated in its response body due to read timeout (buffered, no content-length)
--- config
    location /proxy {
        internal;

        proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.0 200 OK\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
conn err: 110: upstream timed out
upstream fin req: error=0 eof=0 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: 
truncated: true

--- error_log
upstream timed out



=== TEST 50: subrequests truncated in its response body due to premature connection close (nonbuffered, no content-length)
--- config
    server_tokens off;

    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.0 200 OK\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=0
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: false

--- no_error_log
[error]



=== TEST 51: subrequests truncated in its response body due to read timeout (nonbuffered, no content-length)
--- config
    location /proxy {
        internal;

        proxy_read_timeout 500ms;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.0 200 OK\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
conn err: 110: upstream timed out
upstream fin req: error=0 eof=0 rc=504
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true

--- error_log
upstream timed out



=== TEST 52: forwarding in-memory request bodies to multiple subrequests
--- config
    location /other {
        default_type 'foo/bar';
        proxy_pass http://127.0.0.1:$server_port/back;
    }

    location /back {
        echo_read_request_body;
        echo_request_body;
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()

            for i = 1, 2 do
                local res = ngx.location.capture("/other",
                    { method = ngx.HTTP_POST });

                ngx.say(res.body)
            end
        ';
    }

--- request eval
"POST /lua
" . "hello world"

--- response_body
hello world
hello world

--- no_error_log
[error]



=== TEST 53: forwarding in-file request bodies to multiple subrequests (client_body_in_file_only)
--- config
    location /other {
        default_type 'foo/bar';
        proxy_pass http://127.0.0.1:$server_port/back;
    }

    location /back {
        echo_read_request_body;
        echo_request_body;
    }

    client_body_in_file_only on;

    location /lua {
        content_by_lua '
            ngx.req.read_body()

            for i = 1, 2 do
                local res = ngx.location.capture("/other",
                    { method = ngx.HTTP_POST });

                ngx.say(res.body)
            end
        ';
    }

--- request eval
"POST /lua
" . "hello world"

--- response_body
hello world
hello world

--- no_error_log
[error]



=== TEST 54: forwarding in-file request bodies to multiple subrequests (exceeding client_body_buffer_size)
--- config
    location /other {
        default_type 'foo/bar';
        proxy_pass http://127.0.0.1:$server_port/back;
    }

    location /back {
        echo_read_request_body;
        echo_request_body;
    }

    location /lua {
        #client_body_in_file_only on;
        client_body_buffer_size 1;
        content_by_lua '
            ngx.req.read_body()

            for i = 1, 2 do
                local res = ngx.location.capture("/other",
                    { method = ngx.HTTP_POST });

                ngx.say(res.body)
            end
        ';
    }
--- request eval
"POST /lua
" . ("hello world" x 100)

--- stap2
global valid = 0
global fds

F(ngx_http_handler) { valid = 1  }

probe syscall.open {
    if (valid && pid() == target()) {
        print(name, "(", argstr, ")")
    }
}

probe syscall.close {
    if (valid && pid() == target() && fds[sprintf("%d", $fd)]) {
        println(name, "(", argstr, ")")
    }
}

probe syscall.unlink {
    if (valid && pid() == target()) {
        println(name, "(", argstr, ")")
    }
}

probe syscall.open.return {
    if (valid && pid() == target()) {
        println(" = ", retstr)
        fds[retstr] = 1
    }
}

F(ngx_http_lua_subrequest) {
    println("lua subrequest")
}

F(ngx_output_chain) {
    printf("output chain: %s\n", ngx_chain_dump($in))
}

F(ngx_pool_run_cleanup_file) {
    println("clean up file: ", $fd)
}

--- response_body eval
("hello world" x 100) . "\n"
. ("hello world" x 100) . "\n"

--- no_error_log
[error]
--- error_log
a client request body is buffered to a temporary file



=== TEST 55: subrequests truncated in its response body due to premature connection close (buffered + chunked)
--- config
    server_tokens off;

    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_http_version 1.1;
        proxy_buffering on;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\nhello world\r"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true

--- error_log
upstream prematurely closed connection



=== TEST 56: subrequests truncated in its response body due to premature connection close (nonbuffered + chunked)
--- config
    server_tokens off;

    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_http_version 1.1;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\nhello world\r"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true

--- error_log
upstream prematurely closed connection



=== TEST 57: subrequests truncated in its response body due to read timeout (buffered + chunked)
--- config
    location /proxy {
        internal;

        proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\nhello world\r"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
conn err: 110: upstream timed out
upstream fin req: error=0 eof=0 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: 
truncated: true

--- error_log
upstream timed out



=== TEST 58: good chunked response (buffered)
--- config
    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering on;
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=0 rc=0
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello
truncated: false



=== TEST 59: good chunked response (nonbuffered)
--- config
    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_no_close
--- tcp_reply eval
"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=0 rc=0
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello
truncated: false



=== TEST 60: subrequests truncated in its response body due to premature connection close (nonbuffered + proxy)
--- config
    server_tokens off;

    location /proxy {
        internal;

        #proxy_read_timeout 100ms;
        proxy_buffering off;
        proxy_pass http://127.0.0.1:19113;
    }

    location /main {
        content_by_lua '
            local res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
            ngx.say("truncated: ", res.truncated)
        ';
    }
--- request
GET /main
--- tcp_listen: 19113
--- tcp_query_len: 65
--- tcp_reply eval
"HTTP/1.0 200 OK\r\nContent-Length: 1024\r\n\r\nhello world"

--- stap
F(ngx_http_upstream_finalize_request) {
    printf("upstream fin req: error=%d eof=%d rc=%d\n",
        $r->upstream->peer->connection->read->error,
        $r->upstream->peer->connection->read->eof,
        $rc)
    #print_ubacktrace()
}
F(ngx_connection_error) {
    printf("conn err: %d: %s\n", $err, user_string($text))
    #print_ubacktrace()
}
F(ngx_http_lua_post_subrequest) {
    printf("post subreq: rc=%d, status=%d\n", $rc, $r->headers_out->status)
    #print_ubacktrace()
}
/*
F(ngx_http_finalize_request) {
    printf("finalize: %d\n", $rc)
}
*/
--- stap_out
upstream fin req: error=0 eof=1 rc=502
post subreq: rc=0, status=200

--- response_body
status: 200
body: hello world
truncated: true

--- error_log
upstream prematurely closed connection



=== TEST 61: WebDAV methods
--- config
    location /other {
        echo "method: $echo_request_method";
    }

    location /lua {
        content_by_lua '
            local methods = {
                ngx.HTTP_MKCOL,
                ngx.HTTP_COPY,
                ngx.HTTP_MOVE,
                ngx.HTTP_PROPFIND,
                ngx.HTTP_PROPPATCH,
                ngx.HTTP_LOCK,
                ngx.HTTP_UNLOCK,
                ngx.HTTP_PATCH,
                ngx.HTTP_TRACE,
            }

            for i, method in ipairs(methods) do
                local res = ngx.location.capture("/other",
                    { method = method })
                ngx.print(res.body)
            end
        ';
    }
--- request
GET /lua
--- response_body
method: MKCOL
method: COPY
method: MOVE
method: PROPFIND
method: PROPPATCH
method: LOCK
method: UNLOCK
method: PATCH
method: TRACE

--- no_error_log
[error]



=== TEST 62: by default DELETE subrequests don't forward request bodies
--- config
    location /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE });

            ngx.print(res.body)
        ';
    }
--- request
DELETE /lua
hello world
--- response_body
nil
--- no_error_log
[error]



=== TEST 63: DELETE subrequests do forward request bodies when always_forward_body == true
--- config
    location = /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE, always_forward_body = true });

            ngx.print(res.body)
        ';
    }
--- request
DELETE /lua
hello world
--- response_body
hello world
--- no_error_log
[error]



=== TEST 64: DELETE subrequests do forward request bodies when always_forward_body == true (on disk)
--- config
    location = /other {
        default_type 'foo/bar';
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }

    location /lua {
        content_by_lua '
            ngx.req.read_body()
            local res = ngx.location.capture("/other",
                { method = ngx.HTTP_DELETE, always_forward_body = true });

            ngx.print(res.body)
        ';
    }
--- request
DELETE /lua
hello world
--- stap2
global c
probe process("$LIBLUA_PATH").function("rehashtab") {
    c++
    //print_ubacktrace()
    printf("rehash: %d\n", c)
}
--- stap_out2
--- response_body
hello world
--- no_error_log
[error]



=== TEST 65: DELETE
--- config
    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
        ';
    }
    location = /sub {
        echo hello;
        echo world;
    }
--- request
GET /t
--- response_body
hello
world
--- stap
F(ngx_http_lua_capture_header_filter) {
    println("capture header filter")
}

F(ngx_http_lua_capture_body_filter) {
    println("capture body filter")
}

--- stap_out
capture header filter
capture body filter
capture body filter
capture body filter
capture header filter
capture body filter
capture body filter
--- no_error_log
[error]



=== TEST 66: leafo test case 1 for assertion failures
--- config
    location = /t {
        echo hello;
    }

    location /proxy {
        internal;
        rewrite_by_lua "
          local req = ngx.req
          print(ngx.var._url)

          for k,v in pairs(req.get_headers()) do
            if k ~= 'content-length' then
              req.clear_header(k)
            end
          end

          if ngx.ctx.headers then
            for k,v in pairs(ngx.ctx.headers) do
              req.set_header(k, v)
            end
          end
        ";

        proxy_http_version 1.1;
        proxy_pass $_url;
    }

    location /first {
      set $_url "";
      content_by_lua '
        local res = ngx.location.capture("/proxy", {
          ctx = {
            headers = {
              ["Content-type"] = "application/x-www-form-urlencoded"
            }
          },
          vars = { _url = "http://127.0.0.1:" .. ngx.var.server_port .. "/t" }
        })

        ngx.print(res.body)

        local res = ngx.location.capture("/proxy", {
          ctx = {
            headers = {
              ["x-some-date"] = "Sun, 01 Dec 2013 11:47:41 GMT",
              ["x-hello-world-header"] = "123412341234",
              ["Authorization"] = "Hello"
            }
          },
          vars = { _url = "http://127.0.0.1:" .. ngx.var.server_port .. "/t" }
        })

        ngx.print(res.body)
      ';
    }
--- request
GET /first
--- response_body
hello
hello
--- no_error_log eval
[
"[error]",
qr/Assertion .*? failed/
]



=== TEST 67: leafo test case 2 for assertion failures
--- config
    location = /t {
        echo hello;
    }

    location /proxy {
        internal;
        rewrite_by_lua "
          local req = ngx.req
          print(ngx.var._url)

          for k,v in pairs(req.get_headers()) do
            if k ~= 'content-length' then
              req.clear_header(k)
            end
          end

          if ngx.ctx.headers then
            for k,v in pairs(ngx.ctx.headers) do
              req.set_header(k, v)
            end
          end
        ";

        proxy_http_version 1.1;
        proxy_pass $_url;
    }

    location /second {
      set $_url "";
      content_by_lua '
        local res = ngx.location.capture("/proxy", {
          method = ngx.HTTP_POST,
          body = ("x"):rep(600),
          ctx = {
            headers = {
              ["Content-type"] = "application/x-www-form-urlencoded"
            }
          },
          vars = { _url = "http://127.0.0.1:" .. ngx.var.server_port .. "/t" }
        })

        ngx.print(res.body)

        local res = ngx.location.capture("/proxy", {
          ctx = {
            headers = {
              ["x-some-date"] = "Sun, 01 Dec 2013 11:47:41 GMT",
              ["x-hello-world-header"] = "123412341234",
              ["Authorization"] = "Hello"
            }
          },
          vars = { _url = "http://127.0.0.1:" .. ngx.var.server_port .. "/t" }
        })

        ngx.print(res.body)

        local res = ngx.location.capture("/proxy", {
          vars = { _url = "http://127.0.0.1:" .. ngx.var.server_port .. "/t" }
        })

        ngx.print(res.body)
      ';
    }
--- request
GET /second
--- response_body
hello
hello
hello
--- no_error_log eval
[
"[error]",
qr/Assertion .*? failed/
]



=== TEST 68: fetch subrequest's builtin request headers
--- config
    location = /sub {
        echo "sr: User-Agent: $http_user_agent";
        echo "sr: Host: $http_host";
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("pr: User-Agent: ", ngx.var.http_user_agent)
            ngx.say("pr: Host: ", ngx.var.http_host)
        ';
    }
--- request
    GET /t
--- more_headers
User-Agent: foo
--- response_body
sr: User-Agent: foo
sr: Host: localhost
pr: User-Agent: foo
pr: Host: localhost

--- no_error_log
[error]



=== TEST 69: modify subrequest's builtin request headers
--- config
    location = /sub {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "bar")
        ';
        echo "sr: User-Agent: $http_user_agent";
        echo "sr: Host: $http_host";
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("pr: User-Agent: ", ngx.var.http_user_agent)
            ngx.say("pr: Host: ", ngx.var.http_host)
        ';
    }
--- request
    GET /t
--- more_headers
User-Agent: foo
--- response_body
sr: User-Agent: bar
sr: Host: localhost
pr: User-Agent: foo
pr: Host: localhost

--- no_error_log
[error]



=== TEST 70: modify subrequest's builtin request headers (main req is POST)
--- config
    location = /sub {
        rewrite_by_lua '
            ngx.req.set_header("User-Agent", "bar")
        ';
        echo "sr: User-Agent: $http_user_agent";
        echo "sr: Host: $http_host";
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("pr: User-Agent: ", ngx.var.http_user_agent)
            ngx.say("pr: Host: ", ngx.var.http_host)
        ';
    }
--- request
POST /t
hello world
--- more_headers
User-Agent: foo
--- response_body
sr: User-Agent: bar
sr: Host: localhost
pr: User-Agent: foo
pr: Host: localhost

--- no_error_log
[error]



=== TEST 71: duplicate request headers (main req is POST)
--- config
    location = /sub {
        echo "sr: Cookie: $http_cookie";
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("pr: Cookie: ", ngx.var.http_cookie)
        ';
    }
--- request
POST /t
hello world
--- more_headers
Cookie: foo
Cookie: bar
--- response_body
sr: Cookie: foo; bar
pr: Cookie: foo; bar

--- no_error_log
[error]



=== TEST 72: duplicate request headers (main req is GET)
--- config
    location = /sub {
        echo "sr: Cookie: $http_cookie";
    }

    location = /t {
        content_by_lua '
            local res = ngx.location.capture("/sub")
            ngx.print(res.body)
            ngx.say("pr: Cookie: ", ngx.var.http_cookie)
        ';
    }
--- request
GET /t
--- more_headers
Cookie: foo
Cookie: bar
--- response_body
sr: Cookie: foo; bar
pr: Cookie: foo; bar

--- no_error_log
[error]



=== TEST 73: HEAD subrequest (github #347)
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/index.html",
                { method = ngx.HTTP_HEAD });
            ngx.say("content-length: ", res.header["Content-Length"])
            ngx.say("body: [", res.body, "]")
        ';
    }
--- request
GET /lua
--- response_body_like chop
^content-length: \d+
body: \[\]
$
--- no_error_log
[error]



=== TEST 74: image_filter + ngx.location.capture
ngx_http_image_filter_module's header filter intercepts
the header filter chain so the r->header_sent flag won't
get set right after the header filter chain is first invoked.

--- config

location = /back {
    empty_gif;
}

location = /t {
    image_filter rotate 90;

    content_by_lua '
        local res = ngx.location.capture("/back")
        for k, v in pairs(res.header) do
            ngx.header[k] = v
        end
        ngx.status = res.status
        ngx.print(res.body)
    ';
}

--- request
GET /t
--- response_body_like: .
--- stap
F(ngx_http_image_header_filter) {
    println("image header filter")
}
--- stap_out
image header filter

--- no_error_log
[error]



=== TEST 75: WebDAV + MOVE
--- config
    location = /t {
        content_by_lua_block {
            local file1 = "/file1.txt"
            local file2 = "/file2.txt"
            ngx.req.set_header( "Destination", file2 )
            local res = ngx.location.capture(
                file1, { method = ngx.HTTP_MOVE }
            )

            ngx.say(
                "MOVE ", file1, " -> ", file2,
                ", response status: ", res.status
            )
        }
    }

    location / {
        dav_methods MOVE;
    }

--- user_files
>>> file1.txt
hello, world!

--- request
GET /t

--- response_body
MOVE /file1.txt -> /file2.txt, response status: 204

--- no_error_log
[error]
--- error_code: 200



=== TEST 76: WebDAV + DELETE
--- config
    location = /t {
        content_by_lua_block {
            local file = "/file.txt"
            local res = ngx.location.capture(
                file, { method = ngx.HTTP_DELETE }
            )

            ngx.say(
                "DELETE ", file,
                ", response status: ", res.status
            )
        }
    }

    location / {
        dav_methods DELETE;
    }

--- user_files
>>> file.txt
hello, world!

--- request
GET /t

--- response_body
DELETE /file.txt, response status: 204

--- no_error_log
[error]
--- error_code: 200



=== TEST 77: avoid request smuggling 1/4 (default capture + smuggle in header)
--- http_config
    upstream backend {
        server unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        keepalive 32;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.say("method: ", ngx.var.request_method,
                        ", uri: ", ngx.var.uri,
                        ", X: ", ngx.var.http_x)
            }
        }
    }
--- config
    location /proxy {
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_pass         http://backend/foo;
    }

    location /capture {
        server_tokens off;
        more_clear_headers Date;

        content_by_lua_block {
            local res = ngx.location.capture("/proxy")
            ngx.print(res.body)
        }
    }

    location /t {
        content_by_lua_block {
            local req = [[
GET /capture HTTP/1.1
Host: test.com
Content-Length: 37
Transfer-Encoding: chunked

0

GET /capture HTTP/1.1
Host: test.com
X: GET /bar HTTP/1.0

]]

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send req: ", err)
                return
            end

            ngx.say("req bytes: ", bytes)

            local n_resp = 0

            local reader = sock:receiveuntil("\r\n")
            while true do
                local line, err = reader()
                if line then
                    ngx.say(line)
                    if line == "0" then
                        n_resp = n_resp + 1
                    end

                    if n_resp >= 2 then
                        break
                    end

                else
                    ngx.say("err: ", err)
                    break
                end
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
req bytes: 146
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

1f
method: GET, uri: /foo, X: nil

0

HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

2d
method: GET, uri: /foo, X: GET /bar HTTP/1.0

0
--- no_error_log
[error]
--- skip_nginx
3: >= 1.21.1



=== TEST 78: avoid request smuggling 2/4 (POST capture + smuggle in body)
--- http_config
    upstream backend {
        server unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        keepalive 32;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.say("method: ", ngx.var.request_method,
                        ", uri: ", ngx.var.uri)
            }
        }
    }
--- config
    location /proxy {
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_pass         http://backend/foo;
    }

    location /capture {
        server_tokens off;
        more_clear_headers Date;

        content_by_lua_block {
            ngx.req.read_body()
            local res = ngx.location.capture("/proxy", { method = ngx.HTTP_POST })
            ngx.print(res.body)
        }
    }

    location /t {
        content_by_lua_block {
            local req = [[
GET /capture HTTP/1.1
Host: test.com
Content-Length: 57
Transfer-Encoding: chunked

0

POST /capture HTTP/1.1
Host: test.com
Content-Length: 60

POST /bar HTTP/1.1
Host: test.com
Content-Length: 5

hello

]]

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send req: ", err)
                return
            end

            ngx.say("req bytes: ", bytes)

            local n_resp = 0

            local reader = sock:receiveuntil("\r\n")
            while true do
                local line, err = reader()
                if line then
                    ngx.say(line)
                    if line == "0" then
                        n_resp = n_resp + 1
                    end

                    if n_resp >= 2 then
                        break
                    end

                else
                    ngx.say("err: ", err)
                    break
                end
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
req bytes: 205
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0

HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0
--- no_error_log
[error]
--- skip_nginx
3: >= 1.21.1



=== TEST 79: avoid request smuggling 3/4 (POST capture w/ always_forward_body + smuggle in body)
--- http_config
    upstream backend {
        server unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        keepalive 32;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.say("method: ", ngx.var.request_method,
                        ", uri: ", ngx.var.uri)
            }
        }
    }
--- config
    location /proxy {
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_pass         http://backend/foo;
    }

    location /capture {
        server_tokens off;
        more_clear_headers Date;

        content_by_lua_block {
            ngx.req.read_body()
            local res = ngx.location.capture("/proxy", {
                method = ngx.HTTP_POST,
                always_forward_body = true
            })
            ngx.print(res.body)
        }
    }

    location /t {
        content_by_lua_block {
            local req = [[
GET /capture HTTP/1.1
Host: test.com
Content-Length: 57
Transfer-Encoding: chunked

0

POST /capture HTTP/1.1
Host: test.com
Content-Length: 60

POST /bar HTTP/1.1
Host: test.com
Content-Length: 5

hello

]]

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send req: ", err)
                return
            end

            ngx.say("req bytes: ", bytes)

            local n_resp = 0

            local reader = sock:receiveuntil("\r\n")
            while true do
                local line, err = reader()
                if line then
                    ngx.say(line)
                    if line == "0" then
                        n_resp = n_resp + 1
                    end

                    if n_resp >= 2 then
                        break
                    end

                else
                    ngx.say("err: ", err)
                    break
                end
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
req bytes: 205
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0

HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0
--- no_error_log
[error]
--- skip_nginx
3: >= 1.21.1



=== TEST 80: avoid request smuggling 4/4 (POST capture w/ body + smuggle in body)
--- http_config
    upstream backend {
        server unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        keepalive 32;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.say("method: ", ngx.var.request_method,
                        ", uri: ", ngx.var.uri)
            }
        }
    }
--- config
    location /proxy {
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_pass         http://backend/foo;
    }

    location /capture {
        server_tokens off;
        more_clear_headers Date;

        content_by_lua_block {
            ngx.req.read_body()
            local res = ngx.location.capture("/proxy", {
                method = ngx.HTTP_POST,
                always_forward_body = true,
                body = ngx.req.get_body_data()
            })
            ngx.print(res.body)
        }
    }

    location /t {
        content_by_lua_block {
            local req = [[
GET /capture HTTP/1.1
Host: test.com
Content-Length: 57
Transfer-Encoding: chunked

0

POST /capture HTTP/1.1
Host: test.com
Content-Length: 60

POST /bar HTTP/1.1
Host: test.com
Content-Length: 5

hello

]]

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send req: ", err)
                return
            end

            ngx.say("req bytes: ", bytes)

            local n_resp = 0

            local reader = sock:receiveuntil("\r\n")
            while true do
                local line, err = reader()
                if line then
                    ngx.say(line)
                    if line == "0" then
                        n_resp = n_resp + 1
                    end

                    if n_resp >= 2 then
                        break
                    end

                else
                    ngx.say("err: ", err)
                    break
                end
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
req bytes: 205
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0

HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain
Transfer-Encoding: chunked
Connection: keep-alive

18
method: POST, uri: /foo

0
--- no_error_log
[error]
--- skip_nginx
3: >= 1.21.1



=== TEST 81: bad HTTP method
--- config
    location /other { }

    location /lua {
        content_by_lua_block {
            local res = ngx.location.capture("/other",
                { method = 10240 });
        }
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
unsupported HTTP method: 10240



=== TEST 82: bad requests with both Content-Length and Transfer-Encoding (nginx >= 1.21.1)
--- http_config
    upstream backend {
        server unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        keepalive 32;
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;

        location / {
            content_by_lua_block {
                ngx.say("method: ", ngx.var.request_method,
                        ", uri: ", ngx.var.uri,
                        ", X: ", ngx.var.http_x)
            }
        }
    }
--- config
    location /proxy {
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_pass         http://backend/foo;
    }

    location /capture {
        server_tokens off;
        more_clear_headers Date;

        content_by_lua_block {
            local res = ngx.location.capture("/proxy")
            ngx.print(res.body)
        }
    }

    location /t {
        content_by_lua_block {
            local req = [[
GET /capture HTTP/1.1
Host: test.com
Content-Length: 37
Transfer-Encoding: chunked

0

GET /capture HTTP/1.1
Host: test.com
X: GET /bar HTTP/1.0

]]

            local sock = ngx.socket.tcp()
            sock:settimeout(1000)

            local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_PORT)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send req: ", err)
                return
            end

            ngx.say("req bytes: ", bytes)

            local n_resp = 0

            local reader = sock:receiveuntil("\r\n")
            while true do
                local line, err = reader()
                if line then
                    ngx.say(line)
                    if line == "0" then
                        n_resp = n_resp + 1
                    end

                    if n_resp >= 2 then
                        break
                    end

                else
                    ngx.say("err: ", err)
                    break
                end
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body_like
req bytes: 146
HTTP/1.1 400 Bad Request
--- no_error_log
[error]
--- skip_nginx
3: < 1.21.1
