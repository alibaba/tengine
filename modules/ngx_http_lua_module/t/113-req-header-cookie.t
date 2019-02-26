# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (4 * blocks());

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: clear cookie (with existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", nil)
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t
--- more_headers
Cookie: foo=bar
Cookie: baz=blah

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 2
content: cookies: 0

--- response_body
Cookie foo: 
Cookie baz: 
Cookie: 

--- no_error_log
[error]



=== TEST 2: clear cookie (without existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", nil)
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 0
content: cookies: 0

--- response_body
Cookie foo: 
Cookie baz: 
Cookie: 

--- no_error_log
[error]



=== TEST 3: set one custom cookie (with existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", "boo=123")
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie boo: $cookie_boo";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t
--- more_headers
Cookie: foo=bar
Cookie: baz=blah

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 2
content: cookies: 1

--- response_body
Cookie foo: 
Cookie baz: 
Cookie boo: 123
Cookie: boo=123

--- no_error_log
[error]



=== TEST 4: set one custom cookie (without existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", "boo=123")
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie boo: $cookie_boo";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 0
content: cookies: 1

--- response_body
Cookie foo: 
Cookie baz: 
Cookie boo: 123
Cookie: boo=123

--- no_error_log
[error]



=== TEST 5: set multiple custom cookies (with existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", {"boo=123","foo=78"})
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie boo: $cookie_boo";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t
--- more_headers
Cookie: foo=bar
Cookie: baz=blah

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 2
content: cookies: 2

--- response_body
Cookie foo: 78
Cookie baz: 
Cookie boo: 123
Cookie: boo=123; foo=78

--- no_error_log
[error]



=== TEST 6: set multiple custom cookies (without existing cookies)
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Cookie", {"boo=123", "foo=bar"})
        ';
        echo "Cookie foo: $cookie_foo";
        echo "Cookie baz: $cookie_baz";
        echo "Cookie boo: $cookie_boo";
        echo "Cookie: $http_cookie";
    }
--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: cookies: %d\n", $r->headers_in->cookies->nelts)
}

F(ngx_http_core_content_phase) {
    printf("content: cookies: %d\n", $r->headers_in->cookies->nelts)
}

--- stap_out
rewrite: cookies: 0
content: cookies: 2

--- response_body
Cookie foo: bar
Cookie baz: 
Cookie boo: 123
Cookie: boo=123; foo=bar

--- no_error_log
[error]
