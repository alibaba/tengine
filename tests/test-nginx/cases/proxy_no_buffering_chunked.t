# vi:filetype=perl

use lib 'lib';
use Test::Nginx::LWP;

plan tests => repeat_each() * 2 * blocks();
no_root_location();

run_tests();

__DATA__

=== TEST 35: POST chunked in "helloworld"
--- config
    location /main {
        client_max_body_size 200M;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- chunked_body eval
["hello", "world"]
--- response_body: helloworld

=== TEST 36: POST chunked in ""
--- config
    location /main {
        client_max_body_size 200M;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- chunked_body eval
[""]
--- response_body:

=== TEST 37: POST chunked in "a"
--- config
    location /main {
        client_max_body_size 200M;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- chunked_body eval
["a"]
--- response_body: a

=== TEST 38: POST chunked in "helloworld" delay
--- config
    location /main {
        client_max_body_size 200M;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world"]
--- response_body: helloworld

=== TEST 39: POST chunked in "helloworld", client_body_buffer_size=2
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 2;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world"]
--- response_body: helloworld

=== TEST 40: POST chunked in "helloworld", client_body_buffer_size=1
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 1;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world"]
--- response_body: helloworld

=== TEST 41: POST chunked in "helloworld", client_body_buffer_size=3
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 3;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world"]
--- response_body: helloworld

=== TEST 42: POST chunked in "helloworld", big chunk, 6k
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 3;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world" x 1024, "!" x 1024]
--- response_body eval
"hello" . ("world" x 1024) . ('!' x 1024)

=== TEST 43: POST chunked in "helloworld", big chunk, 500k
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 3;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
POST /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world" x 1024 x 100, "!" x 1024]
--- response_body: nil

=== TEST 44: PUT chunked in "helloworld", big chunk, 6k
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 3;
        proxy_set_header Transfer-Encoding "chunked";
        proxy_set_header Content-length "";
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
PUT /main
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world" x 1024, "!" x 1024]
--- response_body eval
"hello" . ("world" x 1024) . ('!' x 1024)

=== TEST 45: PUT chunked in "helloworld", big chunk, 6k, content-length is 0
--- config
    location /main {
        client_max_body_size 200M;
        client_body_buffer_size 3;
        proxy_request_buffering off;
        proxy_pass http://127.0.0.1:1984/upload;
    }

    location /upload {
        lua_need_request_body on;

        content_by_lua 'ngx.print(ngx.var.request_body)';
    }

--- request
PUT /main
--- more_headers
Content-Length: 0
--- start_chunk_delay: 0.01
--- middle_chunk_delay: 0.01
--- chunked_body eval
["hello", "world" x 1024, "!" x 1024]
--- response_body: nil
