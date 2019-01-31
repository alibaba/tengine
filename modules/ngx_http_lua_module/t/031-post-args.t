# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 6);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /lua {
        lua_need_request_body on;
        content_by_lua '
            local args, err = ngx.req.get_post_args()

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
POST /lua
a=3&b=4&c
--- response_body
a = 3
b = 4
c = true



=== TEST 2: lua_need_request_body off
--- config
    location /lua {
        lua_need_request_body off;
        content_by_lua '
            local args, err = ngx.req.get_post_args()

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
POST /lua
a=3&b=4&c
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: empty request body
--- config
    location /lua {
        lua_need_request_body on;
        content_by_lua '
            local args, err = ngx.req.get_post_args()

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                local val = args[key]
                if type(val) == "table" then
                    ngx.say(key, ": ", table.concat(val, ", "))
                else
                    ngx.say(key, ": ", val)
                end
            end
        ';
    }
--- request
POST /lua
--- response_body



=== TEST 4: max args (limited after normal key=value)
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body();
            local args, err = ngx.req.get_post_args(2)

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
POST /lua
foo=3&bar=4&baz=2
--- response_body
err: truncated
bar = 4
foo = 3
--- error_log
lua hit query args limit 2



=== TEST 5: max args (limited after an orphan key)
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body();
            local args, err = ngx.req.get_post_args(2)

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request
POST /lua
foo=3&bar&baz=2
--- response_body
err: truncated
bar = true
foo = 3
--- error_log
lua hit query args limit 2



=== TEST 6: max args (limited after an empty key, but non-empty values)
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body();
            local args, err = ngx.req.get_post_args(2)

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end

            ngx.say("done")
        ';
    }
--- request
POST /lua
foo=3&=hello&=world
--- response_body
err: truncated
foo = 3
done
--- error_log
lua hit query args limit 2



=== TEST 7: default max 100 args
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body();
            local args, err = ngx.req.get_post_args()

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request eval
my $s = "POST /lua\n";
my $i = 1;
while ($i <= 102) {
    if ($i != 1) {
        $s .= '&';
    }
    $s .= "a$i=$i";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 100) {
    push @k, "a$i";
    $i++;
}
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= " = $&\n";
    }
}
"err: truncated\n" . CORE::join("", @k);
--- timeout: 4
--- error_log
lua hit query args limit 100



=== TEST 8: custom max 102 args
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body()
            local args, err = ngx.req.get_post_args(102)

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request eval
my $s = "POST /lua\n";
my $i = 1;
while ($i <= 103) {
    if ($i != 1) {
        $s .= '&';
    }
    $s .= "a$i=$i";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 102) {
    push @k, "a$i";
    $i++;
}
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= " = $&\n";
    }
}
"err: truncated\n" . CORE::join("", @k);
--- timeout: 4
--- error_log
lua hit query args limit 102



=== TEST 9: custom unlimited args
--- config
    location /lua {
        content_by_lua '
            ngx.req.read_body()
            local args, err = ngx.req.get_post_args(0)

            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(args) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, " = ", args[key])
            end
        ';
    }
--- request eval
my $s = "POST /lua\n";
my $i = 1;
while ($i <= 105) {
    if ($i != 1) {
        $s .= '&';
    }
    $s .= "a$i=$i";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 105) {
    push @k, "a$i";
    $i++;
}
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= " = $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4



=== TEST 10: request body in temp file
--- config
    location /lua {
        lua_need_request_body on;
        client_body_in_file_only clean;
        content_by_lua_block {
            local args, err = ngx.req.get_post_args()

            if err then
                ngx.say("err: ", err)
            end

            if args then
                local keys = {}
                for key, val in pairs(args) do
                    table.insert(keys, key)
                end

                table.sort(keys)
                for i, key in ipairs(keys) do
                    ngx.say(key, " = ", args[key])
                end
            end
        }
    }
--- request
POST /lua
a=3&b=4&c
--- response_body
err: request body in temp file not supported
--- no_error_log
[error]
