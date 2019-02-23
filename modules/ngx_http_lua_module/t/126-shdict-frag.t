# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * 39;

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: merge 2 single-page free blocks (forcibly evicted, merge forward)
--- http_config
    lua_shared_dict dogs 20k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            for i = 1, 2 do
                set_key("foo", string.rep("a", 4000))
                set_key("bar", string.rep("b", 4001))
                set_key("baz", string.rep("c", 8102))

                check_key("foo")
                check_key("bar")
                check_key("baz")
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 4
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok
alloc pages: 1 NOT OK
free pages: 2
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok

--- response_body
successfully set foo.
successfully set bar.
successfully set baz with force.
foo not found
bar not found
found baz: 8102
successfully set foo with force.
successfully set bar.
successfully set baz with force.
foo not found
bar not found
found baz: 8102

--- no_error_log
[error]



=== TEST 2: merge 2 single-page free slabs (forcibly evicted, merge backward)
--- http_config
    lua_shared_dict dogs 20k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            for i = 1, 2 do
                set_key("foo", string.rep("a", 4000))
                set_key("bar", string.rep("b", 4001))
                check_key("foo")
                set_key("baz", string.rep("c", 8102))

                check_key("foo")
                check_key("bar")
                check_key("baz")
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 4
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok
alloc pages: 1 NOT OK
free pages: 2
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok

--- response_body
successfully set foo.
successfully set bar.
found foo: 4000
successfully set baz with force.
foo not found
bar not found
found baz: 8102
successfully set foo with force.
successfully set bar.
found foo: 4000
successfully set baz with force.
foo not found
bar not found
found baz: 8102

--- no_error_log
[error]



=== TEST 3: merge 3 single-page free slabs (actively deleted, merge backward AND forward)
--- http_config
    lua_shared_dict dogs 25k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 2 do
                set_key("foo", string.rep("a", 4000))
                set_key("bar", string.rep("b", 4001))
                set_key("baz", string.rep("c", 4002))

                check_key("foo")
                check_key("bar")
                check_key("baz")

                dogs:delete("foo")
                safe_set_key("blah", string.rep("a", 8100))
                dogs:delete("baz")
                safe_set_key("blah", string.rep("a", 8100))
                dogs:delete("bar")
                safe_set_key("blah", string.rep("a", 12010))
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 5
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 3 ok
alloc pages: 1 NOT OK
free pages: 3
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 3 ok

--- response_body
successfully set foo.
successfully set bar.
successfully set baz.
found foo: 4000
found bar: 4001
found baz: 4002
failed to safe set blah: no memory
failed to safe set blah: no memory
successfully safe set blah
successfully set foo with force.
successfully set bar.
successfully set baz.
found foo: 4000
found bar: 4001
found baz: 4002
failed to safe set blah: no memory
failed to safe set blah: no memory
successfully safe set blah

--- no_error_log
[error]



=== TEST 4: merge one single-page block backward, but no more
--- http_config
    lua_shared_dict dogs 25k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                set_key("foo", string.rep("a", 4000))
                set_key("bar", string.rep("b", 4001))
                set_key("baz", string.rep("c", 4002))

                check_key("foo")
                check_key("bar")
                check_key("baz")

                dogs:delete("bar")
                safe_set_key("blah", string.rep("a", 8100))
                dogs:delete("baz")
                safe_set_key("blah", string.rep("a", 8100))
                check_key("foo")
                dogs:delete("foo")
                check_key("blah")
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 5
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok
free pages: 1

--- response_body
successfully set foo.
successfully set bar.
successfully set baz.
found foo: 4000
found bar: 4001
found baz: 4002
failed to safe set blah: no memory
successfully safe set blah
found foo: 4000
found blah: 8100

--- no_error_log
[error]



=== TEST 5: merge one single-page block forward, but no more
--- http_config
    lua_shared_dict dogs 25k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                set_key("foo", string.rep("a", 4000))
                set_key("bar", string.rep("b", 4001))
                set_key("baz", string.rep("c", 4002))

                check_key("foo")
                check_key("bar")
                check_key("baz")

                dogs:delete("bar")
                safe_set_key("blah", string.rep("a", 8100))
                dogs:delete("foo")
                safe_set_key("blah", string.rep("a", 8100))
                check_key("baz")
                dogs:delete("baz")
                check_key("blah")
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 5
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok
free pages: 1

--- response_body
successfully set foo.
successfully set bar.
successfully set baz.
found foo: 4000
found bar: 4001
found baz: 4002
failed to safe set blah: no memory
successfully safe set blah
found baz: 4002
found blah: 8100

--- no_error_log
[error]



=== TEST 6: merge 2 multi-page blocks (forcibly evicted, merge backward)
--- http_config
    lua_shared_dict dogs 30k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                set_key("foo", string.rep("a", 8100))
                set_key("bar", string.rep("b", 8101))
                check_key("foo")
                safe_set_key("baz", string.rep("c", 16300))
                dogs:delete("foo")
                check_key("bar")
                dogs:delete("bar")
                safe_set_key("baz", string.rep("c", 16300))

                check_key("foo")
                check_key("bar")
                check_key("baz")
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 6
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 2 ok
alloc pages: 2 ok
alloc pages: 4 NOT OK
free pages: 2
free pages: 2
alloc pages: 4 ok

--- response_body
successfully set foo.
successfully set bar.
found foo: 8100
failed to safe set baz: no memory
found bar: 8101
successfully safe set baz
foo not found
bar not found
found baz: 16300

--- no_error_log
[error]



=== TEST 7: merge big slabs (less than max slab size) backward
--- http_config
    lua_shared_dict dogs 20k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                for j = 1, 50 do
                    dogs:set("foo" .. j, string.rep("a", 5))
                end
                set_key("bar", string.rep("a", 4000))

                for j = 1, 50 do
                    dogs:delete("foo" .. j)
                end

                safe_set_key("baz", string.rep("b", 8100))
                check_key("bar")

                ngx.say("delete bar")
                dogs:delete("bar")

                safe_set_key("baz", string.rep("b", 8100))
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        //printf("slab max size: %d\n", @var("ngx_slab_max_size"))
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 4
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
free pages: 1
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 ok

--- response_body
successfully set bar.
failed to safe set baz: no memory
found bar: 4000
delete bar
successfully safe set baz

--- no_error_log
[error]



=== TEST 8: cannot merge in-used big slabs page (backward)
--- http_config
    lua_shared_dict dogs 20k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                for j = 1, 63 do
                    dogs:set("foo" .. j, string.rep("a", 5))
                end
                set_key("bar", string.rep("a", 4000))

                --[[
                for j = 1, 50 do
                    dogs:delete("foo" .. j)
                end
                ]]

                safe_set_key("baz", string.rep("b", 8100))
                check_key("bar")

                ngx.say("delete bar")
                dogs:delete("bar")

                safe_set_key("baz", string.rep("b", 8100))
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        //printf("slab max size: %d\n", @var("ngx_slab_max_size"))
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 4
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK

--- response_body
successfully set bar.
failed to safe set baz: no memory
found bar: 4000
delete bar
failed to safe set baz: no memory

--- no_error_log
[error]



=== TEST 9: cannot merge in-used big slabs page (forward)
--- http_config
    lua_shared_dict dogs 20k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs

            local function check_key(key)
                local res, err = dogs:get(key)
                if res then
                    ngx.say("found ", key, ": ", #res)
                else
                    if not err then
                        ngx.say(key, " not found")
                    else
                        ngx.say("failed to fetch key: ", err)
                    end
                end
            end

            local function set_key(key, value)
                local ok, err, force = dogs:set(key, value)
                if ok then
                    ngx.print("successfully set ", key)
                    if force then
                        ngx.say(" with force.")
                    else
                        ngx.say(".")
                    end
                else
                    ngx.say("failed to set ", key, ": ", err)
                end
            end

            local function safe_set_key(key, value)
                local ok, err = dogs:safe_set(key, value)
                if ok then
                    ngx.say("successfully safe set ", key)
                else
                    ngx.say("failed to safe set ", key, ": ", err)
                end
            end

            for i = 1, 1 do
                set_key("bar", string.rep("a", 4000))
                for j = 1, 50 do
                    dogs:set("foo" .. j, string.rep("a", 5))
                end

                --[[
                for j = 1, 50 do
                    dogs:delete("foo" .. j)
                end
                ]]

                safe_set_key("baz", string.rep("b", 8100))
                check_key("bar")

                ngx.say("delete bar")
                dogs:delete("bar")

                safe_set_key("baz", string.rep("b", 8100))
            end

            collectgarbage()
        ';
    }
--- request
GET /test
--- stap
global first_time = 1
global active = 1

F(ngx_http_lua_shdict_init_zone) {
    active = 0
}

F(ngx_http_lua_shdict_init_zone).return {
    active = 1
}

F(ngx_slab_alloc_pages) {
    if (first_time) {
        //printf("slab max size: %d\n", @var("ngx_slab_max_size"))
        printf("total pages: %d\n", $pool->pages->slab)
        first_time = 0
    }
    if (active) {
        printf("alloc pages: %d", $pages)
        //print_ubacktrace()
    } else {
        printf("init zone alloc pages: %d", $pages)
    }
}

F(ngx_slab_alloc_pages).return {
    if ($return) {
        printf(" ok\n")

    } else {
        printf(" NOT OK\n")
    }
}

F(ngx_slab_free_pages) {
    printf("free pages: %d\n", $pages)
}

--- stap_out
total pages: 4
init zone alloc pages: 1 ok
init zone alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 1 ok
alloc pages: 2 NOT OK
free pages: 1
alloc pages: 2 NOT OK

--- response_body
successfully set bar.
failed to safe set baz: no memory
found bar: 4000
delete bar
failed to safe set baz: no memory

--- no_error_log
[error]



=== TEST 10: fuzz testing
--- http_config
    lua_shared_dict dogs 200k;
--- config
    location = /t {
        content_by_lua '
            local rand = math.random
            local dogs = ngx.shared.dogs
            local maxsz = 9000
            local maxkeyidx = 30
            local rep = string.rep

            math.randomseed(ngx.time())
            for i = 1, 30000 do
                local key = "mylittlekey" .. rand(maxkeyidx)
                local ok, err = dogs:get(key)
                if not ok or rand() > 0.6 then
                    local sz = rand(maxsz)
                    local val = rep("a", sz)
                    local ok, err, forcible = dogs:set(key, val)
                    if err then
                        ngx.log(ngx.ERR, "failed to set key: ", err)
                        -- return
                    end
                    if forcible then
                        -- error("forcible")
                    end
                end
            end
            ngx.say("ok")
            collectgarbage()
        ';
    }
--- request
GET /t
--- response_body
ok

--- no_error_log
[error]
--- timeout: 60
