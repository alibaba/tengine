# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: HTTP 1.1
--- config
    location /t {
        content_by_lua '
            ngx.say(ngx.req.http_version())
        ';
    }
--- request
GET /t
--- response_body
1.1
--- no_error_log
[error]



=== TEST 2: HTTP 1.0
--- config
    location /t {
        content_by_lua '
            ngx.say(ngx.req.http_version())
        ';
    }
--- request
GET /t HTTP/1.0
--- response_body
1
--- no_error_log
[error]
