# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: If-None-Match true
--- config
    location /t {
        content_by_lua '
            ngx.header["ETag"] = "123456789"
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:59 GMT"
            ngx.say(ngx.var.http_if_none_match)
        ';
    }
--- request
GET /t
--- more_headers
If-None-Match: 123456789
If-Modified-Since: Thu, 10 May 2012 07:50:59 GMT
--- response_body
--- error_code: 304
--- no_error_log
[error]



=== TEST 2: If-None-Match false
--- config
    location /t {
        etag on;
        content_by_lua '
            ngx.header["ETag"] = "123456789"
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:59 GMT"
            ngx.say(ngx.var.http_if_none_match)
        ';
    }
--- request
GET /t
--- more_headers
If-None-Match: 123456780
If-Modified-Since: Thu, 10 May 2012 07:50:59 GMT
--- response_body
123456780
--- no_error_log
[error]
--- skip_nginx: 3: < 1.3.3



=== TEST 3: Etag clear
--- config
    location /t {
        etag on;
        content_by_lua '
            ngx.header["ETag"] = "123456789"
            ngx.header.last_modified = "Thu, 10 May 2012 07:50:59 GMT"
            ngx.header["ETag"] = nil
            ngx.say(ngx.var.http_if_none_match)
        ';
    }
--- request
GET /t
--- more_headers
If-None-Match: 123456789
If-Modified-Since: Thu, 10 May 2012 07:50:59 GMT
--- response_body
123456789
--- no_error_log
[error]
--- skip_nginx: 3: < 1.3.3
