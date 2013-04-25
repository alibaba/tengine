# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * 10;

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
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



=== TEST 2: error(nil)
--- config
    location /lua {
        content_by_lua
        '   function bar()
                error(nil)
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
lua entry thread aborted: runtime error: unknown reason
stack traceback:
 in function 'error'
: in function 'bar'
:5: in function 'foo'
:7: in function <[string "content_by_lua"]:1>

