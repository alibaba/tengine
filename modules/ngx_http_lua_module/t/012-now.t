# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: use ngx.localtime in content_by_lua
--- config
    location = /now {
        content_by_lua 'ngx.say(ngx.localtime())';
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 2: use ngx.localtime in set_by_lua
--- config
    location = /now {
        set_by_lua $a 'return ngx.localtime()';
        echo $a;
    }
--- request
GET /now
--- response_body_like: ^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$



=== TEST 3: use ngx.time in set_by_lua
--- config
    location = /time {
        set_by_lua $a 'return ngx.time()';
        echo $a;
    }
--- request
GET /time
--- response_body_like: ^\d{10,}$



=== TEST 4: use ngx.time in content_by_lua
--- config
    location = /time {
        content_by_lua 'ngx.say(ngx.time())';
    }
--- request
GET /time
--- response_body_like: ^\d{10,}$



=== TEST 5: use ngx.time in content_by_lua
--- config
    location = /time {
        content_by_lua '
            ngx.say(ngx.time())
            ngx.say(ngx.localtime())
            ngx.say(ngx.utctime())
            ngx.say(ngx.cookie_time(ngx.time()))
        ';
    }
--- request
GET /time
--- response_body_like chomp
^\d{10,}
\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}
\w+, .*? GMT$



=== TEST 6: use ngx.now in set_by_lua
--- config
    location = /time {
        set_by_lua $a 'return ngx.now()';
        echo $a;
    }
--- request
GET /time
--- response_body_like: ^\d{10,}(\.\d{1,3})?$



=== TEST 7: use ngx.now in content_by_lua
--- config
    location = /time {
        content_by_lua 'ngx.say(ngx.now())';
    }
--- request
GET /time
--- response_body_like: ^\d{10,}(\.\d{1,3})?$



=== TEST 8: use ngx.update_time & ngx.now in content_by_lua
--- config
    location = /time {
        content_by_lua '
            ngx.update_time()
            ngx.say(ngx.now())
        ';
    }
--- request
GET /time
--- response_body_like: ^\d{10,}(\.\d{1,3})?$
