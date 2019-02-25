# vim:set ft= ts=4 sw=4 et fdm=marker:

our $SkipReason;

BEGIN {
    if ($ENV{TEST_NGINX_CHECK_LEAK}) {
        $SkipReason = "unavailable for the hup tests";

    } else {
        $ENV{TEST_NGINX_USE_HUP} = 1;
        undef $ENV{TEST_NGINX_USE_STAP};
    }
}

use Test::Nginx::Socket::Lua 'no_plan';

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(1);

#plan tests => repeat_each() * (blocks() * 3 + 3);

#no_diff();
#no_long_string();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: no error in init before HUP
--- http_config
    init_by_lua_block {
        foo = "hello, FOO"
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(foo)
        }
    }
--- request
GET /lua
--- response_body
hello, FOO
--- no_error_log
[error]



=== TEST 2: error in init after HUP (master still alive, worker process still the same as before)
--- http_config
    init_by_lua_block {
        error("failed to init")
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(foo)
        }
    }
--- request
GET /lua
--- response_body
hello, FOO
--- error_log
failed to init
--- reload_fails



=== TEST 3: no error in init again
--- http_config
    init_by_lua_block {
        foo = "hello, foo"
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say(foo)
        }
    }
--- request
GET /lua
--- response_body
hello, foo
--- no_error_log
[error]



=== TEST 4: no error in init before HUP, used ngx.shared.DICT
--- http_config
    lua_shared_dict dogs 1m;

    init_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("foo", "hello, FOO")
    }
--- config
    location /lua {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local foo = dogs:get("foo")
            ngx.say(foo)
        }
    }
--- request
GET /lua
--- response_body
hello, FOO
--- no_error_log
[error]



=== TEST 5: error in init after HUP, not reloaded but foo have changed.
--- http_config
    lua_shared_dict dogs 1m;

    init_by_lua_block {
        local dogs = ngx.shared.dogs
        dogs:set("foo", "foo have changed")

        error("failed to init")
    }
--- config
    location /lua {
        content_by_lua_block {
            ngx.say("HUP reload failed")
        }
    }
--- request
GET /lua
--- response_body
foo have changed
--- error_log
failed to init
--- reload_fails



=== TEST 6: no error in init again, reload success and foo still have changed.
--- http_config
    lua_shared_dict dogs 1m;

    init_by_lua_block {
        -- do nothing
    }
--- config
    location /lua {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local foo = dogs:get("foo")
            ngx.say(foo)
            ngx.say("reload success")
        }
    }
--- request
GET /lua
--- response_body
foo have changed
reload success
--- no_error_log
[error]
