# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#master_on();
#workers(1);
#worker_connections(1014);
#log_level('warn');
#master_process_enabled(1);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 11);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

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
            res = ngx.location.capture("/other",
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
            res = ngx.location.capture("/foo",
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
            res = ngx.location.capture("/other",
                { method = ngx.HTTP_HEAD });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
HEAD
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
            res = ngx.location.capture("/foo",
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
            res = ngx.location.capture("/foo")

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
            res = ngx.location.capture("/foo", {})

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
GET
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
--- error_log
attempt to use a non-string key in the "args" option table



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
--- error_log
attempt to use a non-string key in the "args" option table



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
--- no_error_log
[error]



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
--- no_error_log
[error]



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
            res = ngx.location.capture("/sub", { ctx = ngx.ctx })
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



=== TEST 40: encode args table with a multi-value arg.
--- config
    location /t {
        content_by_lua '
            local args = ngx.req.get_uri_args()
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
r%5b%5d=http%3a%2f%2fajax.googleapis.com%3a80%2fajax%2flibs%2fjquery%2f1.7.2%2fjquery.min.js&r%5b%5d=http%3a%2f%2fajax.googleapis.com%3a80%2fajax%2flibs%2fdojo%2f1.7.2%2fdojo%2fdojo.js.uncompressed.js
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
            res = ngx.location.capture("/sub")
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
            res = ngx.location.capture("/sub")
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
            res = ngx.location.capture("/sub")
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
            res = ngx.location.capture("/memc")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        ';
    }
--- request
GET /main
--- tcp_listen: 19112
--- tcp_query_len: 9
--- tcp_reply eval
"VALUE foo 0 1024\r\nhello world"

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
post subreq: rc=0, status=502

--- response_body
status: 502
body: hello world
--- no_error_log
[error]



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
            res = ngx.location.capture("/memc")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
        ';
    }
--- request
GET /main
--- tcp_listen: 19112
--- tcp_no_close
--- tcp_reply eval
"VALUE foo 0 1024\r\nhello world"

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
post subreq: rc=0, status=504

--- response_body_like chop
^status: 504
body: 

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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
post subreq: rc=0, status=502

--- response_body
status: 502
body: hello world
--- no_error_log
[error]



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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
post subreq: rc=0, status=502

--- response_body
status: 502
body: 
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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
post subreq: rc=0, status=502

--- response_body
status: 502
body: 
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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
            res = ngx.location.capture("/proxy")
            ngx.say("status: ", res.status)
            ngx.say("body: ", res.body)
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
post subreq: rc=0, status=504

--- response_body
status: 504
body: hello world
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
                res = ngx.location.capture("/other",
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
                res = ngx.location.capture("/other",
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
                res = ngx.location.capture("/other",
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

