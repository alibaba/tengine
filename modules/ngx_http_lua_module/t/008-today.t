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

=== TEST 1: use ngx.today in content_by_lua
--- config
    location = /today {
        content_by_lua 'ngx.say(ngx.today())';
    }
--- request
GET /today
--- response_body_like: ^\d{4}-\d{2}-\d{2}$



=== TEST 2: use ngx.today in set_by_lua
--- config
    location = /today {
        set_by_lua $a 'return ngx.today()';
        echo $a;
    }
--- request
GET /today
--- response_body_like: ^\d{4}-\d{2}-\d{2}$
