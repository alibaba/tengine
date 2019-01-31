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

=== TEST 1: clear the Connection req header
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Connection", nil);
        ';

        echo "connection: $http_connection";
    }
--- request
GET /req-header

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: conn type: %d\n", $r->headers_in->connection_type)
}


F(ngx_http_core_content_phase) {
    printf("content: conn type: %d\n", $r->headers_in->connection_type)
}

--- stap_out
rewrite: conn type: 1
content: conn type: 0

--- response_body
connection: 
--- no_error_log
[error]



=== TEST 2: set custom Connection req header (close)
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Connection", "CLOSE");
        ';

        echo "connection: $http_connection";
    }
--- request
GET /req-header

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: conn type: %d\n", $r->headers_in->connection_type)
}


F(ngx_http_core_content_phase) {
    printf("content: conn type: %d\n", $r->headers_in->connection_type)
}

--- stap_out
rewrite: conn type: 1
content: conn type: 1

--- response_body
connection: CLOSE
--- no_error_log
[error]



=== TEST 3: set custom Connection req header (keep-alive)
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Connection", "keep-alive");
        ';

        echo "connection: $http_connection";
    }
--- request
GET /req-header

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: conn type: %d\n", $r->headers_in->connection_type)
}


F(ngx_http_core_content_phase) {
    printf("content: conn type: %d\n", $r->headers_in->connection_type)
}

--- stap_out
rewrite: conn type: 1
content: conn type: 2

--- response_body
connection: keep-alive
--- no_error_log
[error]



=== TEST 4: set custom Connection req header (bad)
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Connection", "bad");
        ';

        echo "connection: $http_connection";
    }
--- request
GET /req-header

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    printf("rewrite: conn type: %d\n", $r->headers_in->connection_type)
}


F(ngx_http_core_content_phase) {
    printf("content: conn type: %d\n", $r->headers_in->connection_type)
}

--- stap_out
rewrite: conn type: 1
content: conn type: 0

--- response_body
connection: bad
--- no_error_log
[error]
