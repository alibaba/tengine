# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

#repeat_each(120);
repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 2);

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
--- response_body_like: 500 Internal Server Error
--- error_code: 500



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

