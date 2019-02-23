# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 19);

#no_diff();
#no_long_string();
#master_on();
#workers(2);
run_tests();

__DATA__

=== TEST 1: read buffered body
--- config
    location = /test {
        access_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
        content_by_lua return;
    }
--- request
POST /test
hello, world
--- response_body
hello, world



=== TEST 2: read buffered body (timed out)
--- config
    client_body_timeout 1ms;
    location = /test {
        access_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
        content_by_lua return;
    }
--- raw_request eval
"POST /test HTTP/1.1\r
Host: localhost\r
Content-Length: 100\r
Connection: close\r
\r
hello, world"
--- response_body:
--- error_code_like: ^(?:500)?$



=== TEST 3: read buffered body and then subrequest
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        access_by_lua '
            ngx.req.read_body()
            local res = ngx.location.capture("/foo");
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
        content_by_lua return;
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo



=== TEST 4: first subrequest and then read buffered body
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        access_by_lua '
            local res = ngx.location.capture("/foo");
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
        content_by_lua return;
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo



=== TEST 5: failed to write 100 continue
--- config
    location = /test {
        access_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
            ngx.exit(200)
        ';
    }
--- request
POST /test
hello, world
--- more_headers
Expect: 100-Continue
--- ignore_response
--- no_error_log
[alert]
[error]
http finalize request: 500, "/test?" a:1, c:0



=== TEST 6: not discard body (exit 200)
--- config
    location = /foo {
        access_by_lua '
            -- ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
            ngx.exit(200)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
"body: hiya, world\n",
]
--- error_code eval
[200, 200]
--- no_error_log
[error]
[alert]



=== TEST 7: not discard body (exit 201)
--- config
    location = /foo {
        access_by_lua '
            -- ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
            ngx.exit(201)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
"body: hiya, world\n",
]
--- error_code eval
[200, 200]
--- no_error_log
[error]
[alert]



=== TEST 8: not discard body (exit 302)
--- config
    location = /foo {
        access_by_lua '
            -- ngx.req.discard_body()
            -- ngx.say("body: ", ngx.var.request_body)
            ngx.redirect("/blah")
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
[qr/302 Found/,
"body: hiya, world\n",
]
--- error_code eval
[302, 200]
--- no_error_log
[error]
[alert]
