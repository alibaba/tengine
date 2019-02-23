# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 0);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: incr key with init (key exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:incr("foo", 10502, 1)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
incr: 10534 nil
foo = 10534
--- no_error_log
[error]



=== TEST 2: incr key with init (key not exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:flush_all()
            dogs:set("bah", 32)
            local res, err = dogs:incr("foo", 10502, 1)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
incr: 10503 nil
foo = 10503
--- no_error_log
[error]



=== TEST 3: incr key with init (key expired and size not matched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            for i = 1, 20 do
                dogs:set("bar" .. i, i, 0.001)
            end
            dogs:set("foo", "32", 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err = dogs:incr("foo", 10502, 0)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
incr: 10502 nil
foo = 10502
--- no_error_log
[error]



=== TEST 4: incr key with init (key expired and size matched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            for i = 1, 20 do
                dogs:set("bar" .. i, i, 0.001)
            end
            dogs:set("foo", 32, 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err = dogs:incr("foo", 10502, 0)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
incr: 10502 nil
foo = 10502
--- no_error_log
[error]



=== TEST 5: incr key with init (forcibly override other valid entries)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:flush_all()
            local long_prefix = string.rep("1234567890", 100)
            for i = 1, 1000 do
                local success, err, forcible = dogs:set(long_prefix .. i, i)
                if forcible then
                    dogs:delete(long_prefix .. i)
                    break
                end
            end
            local res, err, forcible = dogs:incr(long_prefix .. "bar", 10502, 0)
            ngx.say("incr: ", res, " ", err, " ", forcible)
            local res, err, forcible = dogs:incr(long_prefix .. "foo", 10502, 0)
            ngx.say("incr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get(long_prefix .. "foo"))
        }
    }
--- request
GET /test
--- response_body
incr: 10502 nil false
incr: 10502 nil true
foo = 10502
--- no_error_log
[error]



=== TEST 6: incr key without init (no forcible returned)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", 1)
            local res, err, forcible = dogs:incr("foo", 1)
            ngx.say("incr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
incr: 2 nil nil
foo = 2
--- no_error_log
[error]



=== TEST 7: incr key (original value is not number)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local res, err = dogs:incr("foo", 1, 0)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- response_body
incr: nil not a number
foo = true
--- no_error_log
[error]



=== TEST 8: init is not number
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local res, err, forcible = dogs:incr("foo", 1, "bar")
            ngx.say("incr: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        }
    }
--- request
GET /test
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log
number expected, got string
