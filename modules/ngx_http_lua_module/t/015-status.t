# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

#repeat_each(120);
repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 9);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: no key found
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.blah_blah == nil and "nil" or "not nil")
        ';
    }
--- request
GET /nil
--- response_body
nil



=== TEST 2: .status found
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.status == nil and "nil" or "not nil")
        ';
    }
--- request
GET /nil
--- response_body
not nil



=== TEST 3: default to 0
--- config
    location /nil {
        content_by_lua '
            ngx.say(ngx.status);
        ';
    }
--- request
GET /nil
--- response_body
0



=== TEST 4: default to 0
--- config
    location /nil {
        content_by_lua '
            ngx.say("blah");
            ngx.say(ngx.status);
        ';
    }
--- request
GET /nil
--- response_body
blah
200



=== TEST 5: set 201
--- config
    location /201 {
        content_by_lua '
            ngx.status = 201;
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201



=== TEST 6: set "201"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "201";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201



=== TEST 7: set "201.7"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "201.7";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- error_code: 201



=== TEST 8: set "abc"
--- config
    location /201 {
        content_by_lua '
            ngx.status = "abc";
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 9: set blah
--- config
    location /201 {
        content_by_lua '
            ngx.blah = 201;
            ngx.say("created");
        ';
    }
--- request
GET /201
--- response_body
created
--- no_error_log
[error]



=== TEST 10: set ngx.status before headers are sent
--- config
    location /t {
        content_by_lua '
            ngx.say("ok")
            ngx.status = 201
        ';
    }
--- request
    GET /t
--- response_body
ok
--- error_code: 200
--- error_log eval
qr/\[error\] .*? attempt to set ngx\.status after sending out response headers/



=== TEST 11: http 1.0 and ngx.status
--- config
    location /nil {
        content_by_lua '
            ngx.status = ngx.HTTP_UNAUTHORIZED
            ngx.say("invalid request")
            ngx.exit(ngx.HTTP_OK)
        ';
    }
--- request
GET /nil HTTP/1.0
--- response_body
invalid request
--- error_code: 401
--- no_error_log
[error]



=== TEST 12: github issue #221: cannot modify ngx.status for responses from ngx_proxy
--- config
    location = /t {
        proxy_pass http://127.0.0.1:$server_port/;
        header_filter_by_lua '
            if ngx.status == 206 then
                ngx.status = ngx.HTTP_OK
            end
        ';
    }

--- request
GET /t

--- more_headers
Range: bytes=0-4

--- response_body chop
<html

--- error_code: 200
--- no_error_log
[error]



=== TEST 13: 101 response has a complete status line
--- config
    location /t {
        content_by_lua '
            ngx.status = 101
            ngx.send_headers()
        ';
    }
--- request
GET /t
--- raw_response_headers_like: ^HTTP/1.1 101 Switching Protocols\r\n
--- error_code: 101
--- no_error_log
[error]



=== TEST 14: reading error status code
--- config
    location = /t {
        content_by_lua 'ngx.say("status = ", ngx.status)';
    }
--- raw_request eval
"GET /t\r\n"
--- http09
--- response_body
status = 9



=== TEST 15: err status
--- config
    location /nil {
        content_by_lua '
            ngx.exit(502)
        ';
        body_filter_by_lua '
            if ngx.arg[2] then
                ngx.log(ngx.WARN, "ngx.status = ", ngx.status)
            end
        ';
    }
--- request
GET /nil
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log
ngx.status = 502
--- no_error_log
[error]



=== TEST 16: ngx.status assignment should clear r->err_status
--- config
location = /t {
    return 502;
    header_filter_by_lua_block {
        if ngx.status == 502 then
            ngx.status = 654
            ngx.log(ngx.WARN, "ngx.status: ", ngx.status)
        end
    }
}
--- request
GET /t
--- response_body_like: Bad Gateway
--- error_log
ngx.status: 654
--- no_error_log
[error]
--- error_code: 654
