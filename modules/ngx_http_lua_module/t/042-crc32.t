# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: short sanity
--- config
    location = /test {
        content_by_lua '
            ngx.say(ngx.crc32_short("hello, world"))
        ';
    }
--- request
GET /test
--- response_body
4289425978



=== TEST 2: long sanity
--- config
    location = /test {
        content_by_lua '
            ngx.say(ngx.crc32_long("hello, world"))
        ';
    }
--- request
GET /test
--- response_body
4289425978



=== TEST 3: long sanity (empty)
--- config
    location = /test {
        content_by_lua '
            ngx.say(ngx.crc32_long(""))
        ';
    }
--- request
GET /test
--- response_body
0
