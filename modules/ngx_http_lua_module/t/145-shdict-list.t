# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 0);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: lpush & lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
1 nil
bar nil
0 nil
nil nil
--- no_error_log
[error]



=== TEST 2: get operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
nil value is a list
--- no_error_log
[error]



=== TEST 3: set operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:set("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
bar nil
--- no_error_log
[error]



=== TEST 4: replace operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:replace("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
bar nil
--- no_error_log
[error]



=== TEST 5: add operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:add("foo", "bar")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
false exists
nil value is a list
--- no_error_log
[error]



=== TEST 6: delete operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:delete("foo")
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
true nil
nil nil
--- no_error_log
[error]



=== TEST 7: incr operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:incr("foo", 1)
            ngx.say(ok, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
push success
nil not a number
nil value is a list
--- no_error_log
[error]



=== TEST 8: get_keys operation on list type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("foo", "bar")
            if len then
                ngx.say("push success")
            else
                ngx.say("push err: ", err)
            end

            local keys, err = dogs:get_keys()
            ngx.say("key: ", keys[1])
        }
    }
--- request
GET /test
--- response_body
push success
key: foo
--- no_error_log
[error]



=== TEST 9: push operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local len, err = dogs:lpush("foo", "bar")
            ngx.say(len, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 10: pop operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local val, err = dogs:lpop("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 11: llen operation on key-value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local ok, err = dogs:set("foo", "bar")
            if ok then
                ngx.say("set success")
            else
                ngx.say("set err: ", err)
            end

            local val, err = dogs:llen("foo")
            ngx.say(val, " ", err)

            local val, err = dogs:get("foo")
            ngx.say(val, " ", err)
        }
    }
--- request
GET /test
--- response_body
set success
nil value not a list
bar nil
--- no_error_log
[error]



=== TEST 12: lpush and lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:lpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
3
2
1
--- no_error_log
[error]



=== TEST 13: lpush and rpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:lpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:rpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
1
2
3
--- no_error_log
[error]



=== TEST 14: rpush and lpop
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            for i = 1, 3 do
                local len, err = dogs:rpush("foo", i)
                if len ~= i then
                    ngx.say("push err: ", err)
                    break
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("foo")
                if not val then
                    ngx.say("pop err: ", err)
                    break
                else
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
1
2
3
--- no_error_log
[error]



=== TEST 15: list removed: expired
--- http_config
    lua_shared_dict dogs 900k;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local N = 100000
            local max = 0

            for i = 1, N do
                local key = string.format("%05d", i)

                local len , err = dogs:lpush(key, i)
                if not len then
                    max = i
                    break
                end
            end

            local keys = dogs:get_keys(0)

            ngx.say("max - 1 matched keys length: ", max - 1 == #keys)

            dogs:flush_all()

            local keys = dogs:get_keys(0)

            ngx.say("keys all expired, left number: ", #keys)

            for i = 100000, 1, -1 do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    ngx.say("loop again, max matched: ", N + 1 - i == max)
                    break
                end
            end

            dogs:flush_all()

            dogs:flush_expired()

            for i = 1, N do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    ngx.say("loop again, max matched: ", i == max)
                    break
                end
            end
        }
    }
--- request
GET /test
--- response_body
max - 1 matched keys length: true
keys all expired, left number: 0
loop again, max matched: true
loop again, max matched: true
--- no_error_log
[error]
--- timeout: 9



=== TEST 16: list removed: forcibly
--- http_config
    lua_shared_dict dogs 900k;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local N = 200000
            local max = 0
            for i = 1, N do
                local ok, err, forcible  = dogs:set(i, i)
                if not ok or forcible then
                    max = i
                    break
                end
            end

            local two = dogs:get(2)

            ngx.say("two == number 2: ", two == 2)

            dogs:flush_all()
            dogs:flush_expired()

            local keys = dogs:get_keys(0)

            ngx.say("no one left: ", #keys)

            for i = 1, N do
                local key = string.format("%05d", i)

                local len, err = dogs:lpush(key, i)
                if not len then
                    break
                end
            end

            for i = 1, max do
                local ok, err = dogs:set(i, i)
                if not ok then
                    ngx.say("set err: ", err)
                    break
                end
            end

            local two = dogs:get(2)

            ngx.say("two == number 2: ", two == 2)
        }
    }
--- request
GET /test
--- response_body
two == number 2: true
no one left: 0
two == number 2: true
--- no_error_log
[error]
--- timeout: 9



=== TEST 17: expire on all types
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local len, err = dogs:lpush("list", "foo")
            if not len then
                ngx.say("push err: ", err)
            end

            local ok, err = dogs:set("key", "bar")
            if not ok then
                ngx.say("set err: ", err)
            end

            local keys = dogs:get_keys(0)

            ngx.say("keys number: ", #keys)

            dogs:flush_all()

            local keys = dogs:get_keys(0)

            ngx.say("keys number: ", #keys)
        }
    }
--- request
GET /test
--- response_body
keys number: 2
keys number: 0
--- no_error_log
[error]



=== TEST 18: long list node
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local long_str = string.rep("foo", 10)

            for i = 1, 3 do
                local len, err = dogs:lpush("list", long_str)
                if not len then
                    ngx.say("push err: ", err)
                end
            end

            for i = 1, 3 do
                local val, err = dogs:lpop("list")
                if val then
                    ngx.say(val)
                end
            end
        }
    }
--- request
GET /test
--- response_body
foofoofoofoofoofoofoofoofoofoo
foofoofoofoofoofoofoofoofoofoo
foofoofoofoofoofoofoofoofoofoo
--- no_error_log
[error]



=== TEST 19: incr on expired list
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs

            local long_str = string.rep("foo", 10 * 1024) -- 30k

            for i = 1, 100 do
                for j = 1, 10 do
                    local key = "list" .. j
                    local len, err = dogs:lpush(key, long_str)
                    if not len then
                        ngx.say("push err: ", err)
                    end
                end

                dogs:flush_all()

                for j = 10, 1, -1 do
                    local key = "list" .. j
                    local newval, err = dogs:incr(key, 1, 0)
                    if not newval then
                        ngx.say("incr err: ", err)
                    end
                end

                dogs:flush_all()
            end

            ngx.say("done")
        }
    }
--- request
GET /test
--- response_body
done
--- no_error_log
[error]



=== TEST 20: push to an expired list
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local len, err = dogs:lpush("cc", "1") --add another list to avoid key"aa" be cleaned (run ‘ngx_http_lua_shdict_expire(ctx, 1)’ may clean key ,ensure key'aa' not clean ,just expired))
            if not len then
                ngx.say("push cc  err: ", err)
            end
            local len, err = dogs:lpush("aa", "1")
            if not len then
                ngx.say("push1 err: ", err)
            end
            local succ, err = dogs:expire("aa", 0.2)
            if not succ then
                ngx.say("expire err: ",err)
            end
            ngx.sleep(0.3) -- list aa expired
            local len, err = dogs:lpush("aa", "2") --push to an expired list may set as a new list
            if not len then
                ngx.say("push2 err: ", err)
            end
            local len, err = dogs:llen("aa") -- new list len is 1
            if not len then
                ngx.say("llen err: ", err)
            else
            ngx.say("aa:len :", dogs:llen("aa"))
            end
        }
    }

--- request
GET /test
--- response_body
aa:len :1
--- no_error_log
[error]



=== TEST 21: push to an expired list then pop many time (more then list len )
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            local len, err = dogs:lpush("cc", "1") --add another list to avoid key"aa" be cleaned (run ‘ngx_http_lua_shdict_expire(ctx, 1)’ may clean key ,ensure key'aa' not clean ,just expired))
            if not len then
                ngx.say("push cc  err: ", err)
            end
            local len, err = dogs:lpush("aa", "1")
            if not len then
                ngx.say("push1 err: ", err)
            end
            local succ, err = dogs:expire("aa", 0.2)
            if not succ then
            ngx.say("expire err: ",err)
            end
            ngx.sleep(0.3) -- list aa expired
            local len, err = dogs:lpush("aa", "2") --push to an expired list may set as a new list
            if not len then
                ngx.say("push2 err: ", err)
            end
            local val, err = dogs:lpop("aa") 
            if not val then
                ngx.say("llen err: ", err)
            end
            local val, err = dogs:lpop("aa")  -- val == nil
            ngx.say("aa list value: ", val)
        }
    }

--- request
GET /test
--- response_body
aa list value: nil
--- no_error_log
[error]



=== TEST 22: lpush return nil
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua_block {
            local dogs = ngx.shared.dogs
            for i = 1, 2920
            do
                local len, err = dogs:lpush("foo", "bar")
            end
            local len, err = dogs:lpush("foo", "bar")
            ngx.say(len)
        }
    }
--- request
GET /test
--- response_body
nil
--- no_error_log
[error]
