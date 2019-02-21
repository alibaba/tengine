# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        content_by_lua '
            local table = {"hello", nil, true, false, 32.5, 56}
            ngx.say(table)
        ';
    }
--- request
GET /lua
--- response_body
helloniltruefalse32.556



=== TEST 2: nested table
--- config
    location /lua {
        content_by_lua '
            local table = {"hello", nil, true, false, 32.5, 56}
            local table2 = {table, "--", table}
            ngx.say(table2)
        ';
    }
--- request
GET /lua
--- response_body
helloniltruefalse32.556--helloniltruefalse32.556



=== TEST 3: non-array table
--- config
    location /lua {
        content_by_lua '
            local table = {foo = 3}
            ngx.say(table)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: bad data type in table
--- config
    location /lua {
        content_by_lua '
            local f = function () return end
            local table = {1, 3, f}
            ngx.say(table)
        ';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500
