# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 5);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: set non-existent variables via "vars" option
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { dog = "hello", cat = 32 }});

            ngx.print(res.body)
        ';
    }

--- stap2

global delta = "  "

F(ngx_http_finalize_request) {
    uri = ngx_http_req_uri($r)
    printf("finalize req %s: %d\n", uri, $rc)
    if ($rc == 500) {
        print_ubacktrace()
    }
}

F(ngx_http_lua_run_thread) {
    uri = ngx_http_req_uri($r)
    printf("lua run thread %s\n", uri)
}

M(http-subrequest-start) {
    r = $arg1
    n = ngx_http_subreq_depth(r)
    pr = ngx_http_req_parent(r)
    printf("%sbegin %s -> %s (%d)\n", ngx_indent(n, delta),
        ngx_http_req_uri(pr),
        ngx_http_req_uri(r),
        n)
}
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_log eval
qr/variable "(dog|cat)" cannot be assigned a value \(maybe you forgot to define it first\?\)/
--- error_code: 500



=== TEST 2: set non-existent variables via "vars" option
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog '';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { dog = "hello", cat = 32 }});

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_log chop
variable "cat" cannot be assigned a value (maybe you forgot to define it first?)
--- error_code: 500



=== TEST 3: good "vars" option: user variables
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog '';
        set $cat '';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { dog = "hello", cat = 32 }});

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
dog = hello
cat = 32



=== TEST 4: bad "vars" option value
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog '';
        set $cat '';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = "hello" });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
Bad vars option value



=== TEST 5: bad "vars" option value value
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog '';
        set $cat '';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { cat = true } });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
attempt to use bad variable value type boolean



=== TEST 6: good "vars" option: builtin variables
--- config
    location /other {
        echo "args: $args";
    }

    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { args = "a=hello&b=32" }});

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body
args: a=hello&b=32



=== TEST 7: setting non-changeable vars
--- config
    location /other {
        echo "query string: $query_string";
    }

    location /lua {
        content_by_lua '
            res = ngx.location.capture("/other",
                { vars = { query_string = "hello" } });

            ngx.print(res.body)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log chop
variable "query_string" not changeable



=== TEST 8: copy all vars
--- config
    location /other {
        set $dog "$dog world";
        echo "$uri dog: $dog";
    }

    location /lua {
        set $dog 'hello';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { copy_all_vars = true });

            ngx.print(res.body)
            ngx.say(ngx.var.uri, ": ", ngx.var.dog)
        ';
    }
--- request
GET /lua
--- response_body
/other dog: hello world
/lua: hello



=== TEST 9: share all vars
--- config
    location /other {
        set $dog "$dog world";
        echo "$uri dog: $dog";
    }

    location /lua {
        set $dog 'hello';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { share_all_vars = true });

            ngx.print(res.body)
            ngx.say(ngx.var.uri, ": ", ngx.var.dog)
        ';
    }
--- request
GET /lua
--- response_body
/other dog: hello world
/lua: hello world



=== TEST 10: vars takes priority over copy_all_vars
--- config
    location /other {
        set $dog "$dog world";
        echo "$uri dog: $dog";
    }

    location /lua {
        set $dog 'hello';
        content_by_lua '
            local res = ngx.location.capture("/other",
                { vars = { dog = "hiya" }, copy_all_vars = true });

            ngx.print(res.body)
            ngx.say(ngx.var.uri, ": ", ngx.var.dog)
        ';
    }
--- request
GET /lua
--- response_body
/other dog: hiya world
/lua: hello



=== TEST 11: capture_multi: good "vars" option: user variables
--- config
    location /other {
        content_by_lua '
            ngx.say("dog = ", ngx.var.dog)
            ngx.say("cat = ", ngx.var.cat)
        ';
    }

    location /lua {
        set $dog 'blah';
        set $cat 'foo';
        content_by_lua '
            local res1, res2 = ngx.location.capture_multi{
                {"/other/1",
                    { vars = { dog = "hello", cat = 32 }}
                },
                {"/other/2",
                    { vars = { dog = "hiya", cat = 56 }}
                }
            };

            ngx.print(res1.body)
            ngx.print(res2.body)
            ngx.say("parent dog: ", ngx.var.dog)
            ngx.say("parent cat: ", ngx.var.cat)
        ';
    }
--- request
GET /lua
--- response_body
dog = hello
cat = 32
dog = hiya
cat = 56
parent dog: blah
parent cat: foo
