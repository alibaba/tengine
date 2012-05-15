# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 5);

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: string key, int value
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set("bah", 10502)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
32 number
10502 number



=== TEST 2: string key, floating-point value
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            cats:set("foo", 3.14159)
            cats:set("baz", 1.28)
            cats:set("baz", 3.96)
            local val = cats:get("foo")
            ngx.say(val, " ", type(val))
            val = cats:get("baz")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
3.14159 number
3.96 number



=== TEST 3: string key, boolean value
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            cats:set("foo", true)
            cats:set("bar", false)
            local val = cats:get("foo")
            ngx.say(val, " ", type(val))
            val = cats:get("bar")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
true boolean
false boolean



=== TEST 4: number keys, string values
--- http_config
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local cats = ngx.shared.cats
            ngx.say(cats:set(1234, "cat"))
            ngx.say(cats:set("1234", "dog"))
            ngx.say(cats:set(256, "bird"))
            ngx.say(cats:get(1234))
            ngx.say(cats:get("1234"))
            local val = cats:get("256")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
truenilfalse
truenilfalse
truenilfalse
dog
dog
bird string



=== TEST 5: different-size values set to the same key
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", "hello")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
hello
hello, world
hello



=== TEST 6: expired entries (can be auto-removed by get)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01)
            ngx.location.capture("/sleep/0.01")
            ngx.say(dogs:get("foo"))
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
nil



=== TEST 7: expired entries (can NOT be auto-removed by get)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 56, 0.001)
            dogs:set("baz", 78, 0.001)
            dogs:set("foo", 32, 0.01)
            ngx.location.capture("/sleep/0.012")
            ngx.say(dogs:get("foo"))
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
nil



=== TEST 8: not yet expired entries
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.5)
            ngx.location.capture("/sleep/0.01")
            ngx.say(dogs:get("foo"))
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
32



=== TEST 9: forcibly override other valid entries
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local i = 0
            while i < 1000 do
                i = i + 1
                local val = string.rep(" hello", 10) .. i
                local res, err, forcible = dogs:set("key_" .. i, val)
                if not res or forcible then
                    ngx.say(res, " ", err, " ", forcible)
                    break
                end
            end
            ngx.say("abort at ", i)
            ngx.say("cur value: ", dogs:get("key_" .. i))
            if i > 1 then
                ngx.say("1st value: ", dogs:get("key_1"))
            end
            if i > 2 then
                ngx.say("2nd value: ", dogs:get("key_2"))
            end
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
my $a = "true nil true\nabort at (353|705)\ncur value: " . (" hello" x 10) . "\\1\n1st value: nil\n2nd value: " . (" hello" x 10) . "2\n";
[qr/$a/,
"true nil true\nabort at 1\ncur value: " . (" hello" x 10) . "1\n"
]



=== TEST 10: forcibly override other valid entries and test LRU
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local i = 0
            while i < 1000 do
                i = i + 1
                local val = string.rep(" hello", 10) .. i
                if i == 10 then
                    dogs:get("key_1")
                end
                local res, err, forcible = dogs:set("key_" .. i, val)
                if not res or forcible then
                    ngx.say(res, " ", err, " ", forcible)
                    break
                end
            end
            ngx.say("abort at ", i)
            ngx.say("cur value: ", dogs:get("key_" .. i))
            if i > 1 then
                ngx.say("1st value: ", dogs:get("key_1"))
            end
            if i > 2 then
                ngx.say("2nd value: ", dogs:get("key_2"))
            end
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
my $a = "true nil true\nabort at (353|705)\ncur value: " . (" hello" x 10) . "\\1\n1st value: " . (" hello" x 10) . "1\n2nd value: nil\n";
[qr/$a/,
"true nil true\nabort at 2\ncur value: " . (" hello" x 10) . "2\n1st value: " . (" hello" x 10) . "1\n"
]



=== TEST 11: dogs and cats dicts
--- http_config
    lua_shared_dict dogs 1m;
    lua_shared_dict cats 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local cats = ngx.shared.cats
            dogs:set("foo", 32)
            cats:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
            ngx.say(cats:get("foo"))
            dogs:set("foo", 56)
            ngx.say(dogs:get("foo"))
            ngx.say(cats:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
32
hello, world
56
hello, world



=== TEST 12: get non-existent keys
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            ngx.say(dogs:get("foo"))
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
nil
nil



=== TEST 13: not feed the object into the call
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local rc, err = pcall(dogs.set, "foo", 3, 0.01)
            ngx.say(rc, " ", err)
            rc, err = pcall(dogs.set, "foo", 3)
            ngx.say(rc, " ", err)
            rc, err = pcall(dogs.get, "foo")
            ngx.say(rc, " ", err)
        ';
    }
--- request
GET /test
--- response_body
false bad argument #1 to '?' (userdata expected, got string)
false expecting 3, 4 or 5 arguments, but only seen 2
false expecting exactly two arguments, but only seen 1



=== TEST 14: too big value
--- http_config
    lua_shared_dict dogs 50k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local res, err, forcible = dogs:set("foo", string.rep("helloworld", 10000))
            ngx.say(res, " ", err, " ", forcible)
        ';
    }
--- request
GET /test
--- response_body
false no memory false



=== TEST 15: too big key
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local key = string.rep("a", 65535)
            local rc, err = dogs:set(key, "hello")
            ngx.say(rc, " ", err)
            ngx.say(dogs:get(key))

            key = string.rep("a", 65536)
            rc, err = pcall(dogs.set, dogs, key, "world")
            ngx.say(rc, " ", err)

        ';
    }
--- request
GET /test
--- response_body
true nil
hello
false the key argument is more than 65535 bytes: 65536



=== TEST 16: bad value type
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local rc, err = pcall(dogs.set, dogs, "foo", dogs)
            ngx.say(rc, " ", err)
        ';
    }
--- request
GET /test
--- response_body
false unsupported value type for key "foo" in shared_dict "dogs": userdata



=== TEST 17: delete after setting values
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            ngx.say(dogs:get("foo"))
            dogs:delete("foo")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
32
nil
hello, world



=== TEST 18: delete at first
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:delete("foo")
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
nil
hello, world



=== TEST 19: set nil after setting values
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", nil)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
32
nil
hello, world



=== TEST 20: set nil at first
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", nil)
            ngx.say(dogs:get("foo"))
            dogs:set("foo", "hello, world")
            ngx.say(dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
nil
hello, world



=== TEST 21: fail to allocate memory
--- http_config
    lua_shared_dict dogs 100k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            local i = 0
            while i < 1000 do
                i = i + 1
                local val = string.rep("hello", i )
                local res, err, forcible = dogs:set("key_" .. i, val)
                if not res or forcible then
                    ngx.say(res, " ", err, " ", forcible)
                    break
                end
            end
            ngx.say("abort at ", i)
        ';
    }
--- request
GET /test
--- response_body_like
^true nil true\nabort at (?:139|140)$



=== TEST 22: string key, int value (write_by_lua)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        rewrite_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set("bah", 10502)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
32 number
10502 number



=== TEST 23: string key, int value (access_by_lua)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        access_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set("bah", 10502)
            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
        content_by_lua return;
    }
--- request
GET /test
--- response_body
32 number
10502 number



=== TEST 24: string key, int value (set_by_lua)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        set_by_lua $res '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            return dogs:get("foo")
        ';
        echo $res;
    }
--- request
GET /test
--- response_body
32



=== TEST 25: string key, int value (header_by_lua)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        echo hello;
        header_filter_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            ngx.header["X-Foo"] = dogs:get("foo")
        ';
    }
--- request
GET /test
--- response_headers
X-Foo: 32
--- response_body
hello



=== TEST 26: too big value (forcible)
--- http_config
    lua_shared_dict dogs 50k;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bah", "hello")
            local res, err, forcible = dogs:set("foo", string.rep("helloworld", 10000))
            ngx.say(res, " ", err, " ", forcible)
        ';
    }
--- request
GET /test
--- response_body
false no memory true



=== TEST 27: add key (key exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err, forcible = dogs:add("foo", 10502)
            ngx.say("add: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
add: false exists false
foo = 32



=== TEST 28: add key (key not exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bah", 32)
            local res, err, forcible = dogs:add("foo", 10502)
            ngx.say("add: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
add: true nil false
foo = 10502



=== TEST 29: add key (key expired)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 32, 0.001)
            dogs:set("baz", 32, 0.001)
            dogs:set("foo", 32, 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err, forcible = dogs:add("foo", 10502)
            ngx.say("add: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
add: true nil false
foo = 10502



=== TEST 30: add key (key expired and value size unmatched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 32, 0.001)
            dogs:set("baz", 32, 0.001)
            dogs:set("foo", "hi", 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err, forcible = dogs:add("foo", "hello")
            ngx.say("add: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
add: true nil false
foo = hello



=== TEST 31: incr key (key exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err, forcible = dogs:replace("foo", 10502)
            ngx.say("replace: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))

            local res, err, forcible = dogs:replace("foo", "hello")
            ngx.say("replace: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))

        ';
    }
--- request
GET /test
--- response_body
replace: true nil false
foo = 10502
replace: true nil false
foo = hello



=== TEST 32: replace key (key not exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bah", 32)
            local res, err, forcible = dogs:replace("foo", 10502)
            ngx.say("replace: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
replace: false not found false
foo = nil



=== TEST 33: replace key (key expired)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 3, 0.001)
            dogs:set("baz", 2, 0.001)
            dogs:set("foo", 32, 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err, forcible = dogs:replace("foo", 10502)
            ngx.say("replace: ", res, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
replace: false not found false
foo = nil



=== TEST 34: replace key (key expired and value size unmatched)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 32, 0.001)
            dogs:set("baz", 32, 0.001)
            dogs:set("foo", "hi", 0.001)
            ngx.location.capture("/sleep/0.002")
            local rc, err, forcible = dogs:replace("foo", "hello")
            ngx.say("replace: ", rc, " ", err, " ", forcible)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
replace: false not found false
foo = nil



=== TEST 35: incr key (key exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:incr("foo", 10502)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: 10534 nil
foo = 10534



=== TEST 36: replace key (key not exists)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bah", 32)
            local res, err = dogs:incr("foo", 2)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: nil not found
foo = nil



=== TEST 37: replace key (key expired)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("bar", 3, 0.001)
            dogs:set("baz", 2, 0.001)
            dogs:set("foo", 32, 0.001)
            ngx.location.capture("/sleep/0.002")
            local res, err = dogs:incr("foo", 10502)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
    location ~ ^/sleep/(.+) {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
incr: nil not found
foo = nil



=== TEST 38: incr key (incr by 0)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:incr("foo", 0)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: 32 nil
foo = 32



=== TEST 39: incr key (incr by floating point number)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:incr("foo", 0.14)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: 32.14 nil
foo = 32.14



=== TEST 40: incr key (incr by negative numbers)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            local res, err = dogs:incr("foo", -0.14)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: 31.86 nil
foo = 31.86



=== TEST 41: incr key (original value is not number)
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", true)
            local res, err = dogs:incr("foo", -0.14)
            ngx.say("incr: ", res, " ", err)
            ngx.say("foo = ", dogs:get("foo"))
        ';
    }
--- request
GET /test
--- response_body
incr: nil not a number
foo = true



=== TEST 42: get and set with flags
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0, 199)
            dogs:set("bah", 10502, 202)
            local val, flags = dogs:get("foo")
            ngx.say(val, " ", type(val))
            ngx.say(flags, " ", type(flags))
            val, flags = dogs:get("bah")
            ngx.say(val, " ", type(val))
            ngx.say(flags, " ", type(flags))
        ';
    }
--- request
GET /test
--- response_body
32 number
199 number
10502 number
nil nil



=== TEST 43: expired entries (can be auto-removed by get), with flags set
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /test {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32, 0.01, 255)
            ngx.location.capture("/sleep/0.01")
            local res, flags = dogs:get("foo")
            ngx.say("res = ", res, ", flags = ", flags)
        ';
    }
    location ~ '^/sleep/(.+)' {
        echo_sleep $1;
    }
--- request
GET /test
--- response_body
res = nil, flags = nil



=== TEST 44: flush_all
--- http_config
    lua_shared_dict dogs 1m;
--- config
    location = /t {
        content_by_lua '
            local dogs = ngx.shared.dogs
            dogs:set("foo", 32)
            dogs:set("bah", 10502)

            local val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))

            dogs:flush_all()

            val = dogs:get("foo")
            ngx.say(val, " ", type(val))
            val = dogs:get("bah")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /t
--- response_body
32 number
10502 number
nil nil
nil nil

