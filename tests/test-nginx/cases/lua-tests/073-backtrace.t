# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * 4;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: basic print
--- config
    location /lua {
        content_by_lua
        '   function bar()
                return lua_concat(3)
            end
            function foo()
                bar()
            end
            foo()
        ';
    }
--- request
GET /lua
--- ignore_response
--- error_log
attempt to call global 'lua_concat'
: in function 'bar'
:5: in function 'foo'
:7: in function

