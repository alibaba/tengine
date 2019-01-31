# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: http_time in content_by_lua
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.http_time(1290079655))
        ';
    }
--- request
GET /lua
--- response_body
Thu, 18 Nov 2010 11:27:35 GMT



=== TEST 2: http_time in set_by_lua
--- config
    location /lua {
        set_by_lua $a '
            return ngx.http_time(1290079655)
        ';
        echo $a;
    }
--- request
GET /lua
--- response_body
Thu, 18 Nov 2010 11:27:35 GMT



=== TEST 3: parse_http_time in set_by_lua
--- config
    location /lua {
        set_by_lua $a '
            return ngx.parse_http_time("Thu, 18 Nov 2010 11:27:35 GMT")
        ';
        echo $a;
    }
--- request
GET /lua
--- response_body
1290079655



=== TEST 4: parse_http_time in content_by_lua
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.parse_http_time("Thu, 18 Nov 2010 11:27:35 GMT"))
        ';
    }
--- request
GET /lua
--- response_body
1290079655



=== TEST 5: bad arg for parse_http_time in content_by_lua
--- config
    location /lua {
        content_by_lua '
            ngx.say(ngx.parse_http_time("abc") or "nil")
        ';
    }
--- request
GET /lua
--- response_body
nil
