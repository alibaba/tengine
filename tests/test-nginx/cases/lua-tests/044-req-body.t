# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 4 + 1);

#no_diff();
no_long_string();
#master_on();
#workers(2);
run_tests();

__DATA__

=== TEST 1: read buffered body
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
--- no_error_log
[error]



=== TEST 2: read buffered body (timed out)
--- config
    client_body_timeout 1ms;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
        ';
    }
--- raw_request eval
"POST /test HTTP/1.1\r
Host: localhost\r
Content-Length: 100\r
Connection: close\r

hello, world"
--- response_body:
--- error_code_like: ^(?:500)?$
--- no_error_log
[error]



=== TEST 3: read buffered body and then subrequest
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            local res = ngx.location.capture("/foo");
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo
--- no_error_log
[error]



=== TEST 4: first subrequest and then read buffered body
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        content_by_lua '
            local res = ngx.location.capture("/foo");
            ngx.req.read_body()
            ngx.say(ngx.var.request_body)
            ngx.say("sub: ", res.body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
sub: foo
--- no_error_log
[error]



=== TEST 5: read_body not allowed in set_by_lua
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        set_by_lua $has_read_body '
            return ngx.req.read_body and "defined" or "undef"
        ';
        echo "ngx.req.read_body: $has_read_body";
    }
--- request
GET /test
--- response_body
ngx.req.read_body: undef
--- no_error_log
[error]



=== TEST 6: read_body not allowed in set_by_lua
--- config
    location /foo {
        echo -n foo;
    }
    location = /test {
        set $bool '';
        header_filter_by_lua '
             ngx.var.bool = (ngx.req.read_body and "defined" or "undef")
        ';
        content_by_lua '
            ngx.send_headers()
            ngx.say("ngx.req.read_body: ", ngx.var.bool)
        ';
    }
--- request
GET /test
--- response_body
ngx.req.read_body: undef
--- no_error_log
[error]



=== TEST 7: discard body
--- config
    location = /foo {
        content_by_lua '
            ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';

    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
"body: hiya, world\n"]
--- no_error_log
[error]



=== TEST 8: not discard body
--- config
    location = /foo {
        content_by_lua '
            -- ngx.req.discard_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
    location = /bar {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: ", ngx.var.request_body)
        ';
    }
--- pipelined_requests eval
["POST /foo
hello, world",
"POST /bar
hiya, world"]
--- response_body eval
["body: nil\n",
qr/400 Bad Request/]
--- error_code eval
[200, '']
--- no_error_log
[error]



=== TEST 9: read buffered body and retrieve the data
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }
--- request
POST /test
hello, world
--- response_body
hello, world
--- no_error_log
[error]



=== TEST 10: read buffered body to file and call get_body_data
--- config
    client_body_in_file_only on;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_data())
        ';
    }
--- request
POST /test
hello, world
--- response_body
nil
--- no_error_log
[error]



=== TEST 11: read buffered body to file and call get_body_file
--- config
    client_body_in_file_only on;
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_file())
        ';
    }
--- request
POST /test
hello, world
--- response_body_like: client_body_temp/
--- no_error_log
[error]



=== TEST 12: read buffered body to memory and retrieve the file
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.say(ngx.req.get_body_file())
        ';
    }
--- request
POST /test
hello, world
--- response_body
nil
--- no_error_log
[error]



=== TEST 13: read buffered body to memory and reset it with data in memory
--- config
    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
            ngx.say(ngx.var.echo_request_body)
        ';
    }
--- request
POST /test
hello, world
--- response_body
hiya, dear
hiya, dear
hiya, dear
--- no_error_log
[error]



=== TEST 14: read body to file and then override it with data in memory
--- config
    client_body_in_file_only on;

    location = /test {
        content_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hello, baby")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
        ';
    }
--- request
POST /test
yeah
--- response_body
hello, baby
hello, baby
--- no_error_log
[error]



=== TEST 15: do not read the current request body but replace it with our own in memory
--- config
    client_body_in_file_only on;

    location = /test {
        content_by_lua '
            ngx.req.set_body_data("hello, baby")
            ngx.say(ngx.req.get_body_data())
            ngx.say(ngx.var.request_body)
            -- ngx.location.capture("/sleep")
        ';
    }
    location = /sleep {
        echo_sleep 0.5;
    }
--- pipelined_requests eval
["POST /test\nyeah", "POST /test\nblah"]
--- response_body eval
["hello, baby
hello, baby
",
"hello, baby
hello, baby
"]
--- no_error_log
[error]



=== TEST 16: read buffered body to file and reset it to a new file
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file()
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
            ngx.var.new = ngx.req.get_body_file()
        ';
        #echo_request_body;
        proxy_pass http://127.0.0.1:$server_port/echo;
        #proxy_pass http://127.0.0.1:7890/echo;
        add_header X-Old $old;
        add_header X-New $new;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- user_files
>>> a.txt
Will you change this world?
--- raw_response_headers_like
X-Old: \S+/client_body_temp/\d+\r
.*?X-New: \S+/html/a\.txt\r
--- response_body
Will you change this world?
--- no_error_log
[error]



=== TEST 17: read buffered body to file and reset it to a new file
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file() or ""
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
            ngx.var.new = ngx.req.get_body_file()
        ';
        #echo_request_body;
        proxy_pass http://127.0.0.1:$server_port/echo;
        #proxy_pass http://127.0.0.1:7890/echo;
        add_header X-Old $old;
        add_header X-New $new;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world!
--- user_files
>>> a.txt
Will you change this world?
--- raw_response_headers_like
X-Old: \S+/client_body_temp/\d+\r
.*?X-New: \S+/html/a\.txt\r
--- response_body
Will you change this world?
--- no_error_log
[error]



=== TEST 18: read buffered body to file and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only on;

    location = /test {
        set $old '';
        set $new '';
        content_by_lua '
            ngx.req.read_body()
            ngx.var.old = ngx.req.get_body_file()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
            local b_file = ngx.var.realpath_root .. "/b.txt"
            ngx.req.set_body_file(b_file, true)
            ngx.say("a.txt exists: ", io.open(a_file) and "yes" or "no")
            ngx.say("b.txt exists: ", io.open(b_file) and "yes" or "no")
        ';
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- user_files
>>> a.txt
Will you change this world?
>>> b.txt
Sure I will!
--- response_body
a.txt exists: no
b.txt exists: yes
--- no_error_log
[error]



=== TEST 19: read buffered body to memoary and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
qr/500 Internal Server Error/]
--- error_code eval
[200, 500]



=== TEST 20: read buffered body to memoary and reset it to a new file (no auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.read_body()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, false)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
"Will you change this world?\n"]
--- error_code eval
[200, 200]
--- no_error_log
[error]



=== TEST 21: no request body and reset it to a new file (auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, false)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
"Will you change this world?\n"]
--- error_code eval
[200, 200]
--- no_error_log
[error]



=== TEST 22: no request body and reset it to a new file (no auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
qr/500 Internal Server Error/]
--- error_code eval
[200, 500]
--- error_log eval
[qr{\[error\].*? lua handler aborted: runtime error: \[string "rewrite_by_lua"\]:3: stat\(\) "[^"]+/a\.txt" failed}
]



=== TEST 23: read buffered body to memory and reset it with data in memory + proxy
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear dear friend!")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- response_body chomp
hiya, dear dear friend!
--- no_error_log
[error]



=== TEST 24: discard request body and reset it to a new file (no auto-clean)
--- config
    client_body_in_file_only off;

    location = /test {
        set $old '';
        set $new '';
        rewrite_by_lua '
            ngx.req.discard_body()
            local a_file = ngx.var.realpath_root .. "/a.txt"
            ngx.req.set_body_file(a_file, true)
        ';
        echo_request_body;
    }
    location /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hey, you"]
--- user_files
>>> a.txt
Will you change this world?
--- response_body eval
["Will you change this world?\n",
qr/500 Internal Server Error/]
--- error_code eval
[200, 500]



=== TEST 25: discard body and then read
--- config
    location = /test {
        content_by_lua '
            ngx.req.discard_body()
            ngx.req.read_body()
            ngx.print(ngx.req.get_body_data())
        ';
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hello, world"]
--- response_body eval
["nil","nil"]
--- no_error_log
[error]



=== TEST 26: set empty request body in memory
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.set_body_data("")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: [", ngx.req.get_body_data(), "]")
        ';
    }
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hello, world"]
--- response_body eval
["body: [nil]\n","body: [nil]\n"]
--- no_error_log
[error]



=== TEST 27: set empty request body in file
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        content_by_lua '
            ngx.req.read_body()
            ngx.say("body: [", ngx.req.get_body_data(), "]")
        ';
    }
--- user_files
>>> a.txt
--- pipelined_requests eval
["POST /test
hello, world",
"POST /test
hello, world"]
--- response_body eval
["body: [nil]\n","body: [nil]\n"]
--- no_error_log
[error]



=== TEST 28: read and set body
--- config
    location /test {
        lua_need_request_body on;
        access_by_lua_file html/myscript.lua;
        echo_request_body;
    }
--- user_files
>>> myscript.lua
    local data, data2 = ngx.req.get_post_args(), {}
    for k, v in pairs(data) do
        if type(v) == "table" then
            for i, val in ipairs(v) do
                local s = ngx.escape_uri(string.upper(k)) .. '='
                        .. ngx.escape_uri(string.upper(val))
                table.insert(data2, s)
            end
        else
            local s = ngx.escape_uri(string.upper(k)) .. '='
                    .. ngx.escape_uri(string.upper(v))
            table.insert(data2, s)
        end
    end
    ngx.req.set_body_data(table.concat(data2, "&"))
--- request
POST /test
a=1&a=2&b=hello&c=world
--- response_body
B=HELLO&A=1&A=2&C=WORLD
--- no_error_log
[error]
--- SKIP



=== TEST 29: read buffered body to memory and reset it with data in memory + proxy twice
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear dear friend!")
            ngx.req.set_body_data("howdy, my dear little sister!")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- response_body chomp
howdy, my dear little sister!
--- no_error_log
[error]



=== TEST 30: read buffered body to memory and reset it with data in memory and then reset it to file
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear dear friend!")
            ngx.req.set_body_file(ngx.var.realpath_root .. "/a.txt")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- user_files
>>> a.txt
howdy, my dear little sister!
--- request
POST /test
hello, world
--- response_body
howdy, my dear little sister!
--- no_error_log
[error]



=== TEST 31: read buffered body to memory and reset it with empty string + proxy twice
--- config
    location = /test {
        rewrite_by_lua '
            ngx.req.read_body()
            ngx.req.set_body_data("hiya, dear dear friend!")
            ngx.req.set_body_data("")
        ';
        proxy_pass http://127.0.0.1:$server_port/echo;
    }
    location = /echo {
        echo_read_request_body;
        echo_request_body;
    }
--- request
POST /test
hello, world
--- response_body chomp
--- no_error_log
[error]



=== TEST 32: multi-buffer request body
--- config
    location /foo {
        default_type text/css;
        srcache_store POST /store;

        echo hello;
        echo world;
    }

    location /store {
        content_by_lua '
            local body = ngx.req.get_body_data()
            ngx.log(ngx.WARN, "srcache_store: request body len: ", #body)
        ';
    }
--- request
GET /foo
--- response_body
hello
world
--- error_log
srcache_store: request body len: 55
--- no_error_log
[error]

