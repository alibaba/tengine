# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);

plan tests => repeat_each() * (2 * blocks() + 48);

#no_diff();
no_long_string();

run_tests();

__DATA__

=== TEST 1: random access req headers
--- config
    location /req-header {
        content_by_lua '
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("Foo: ", headers["Foo"] or "nil")
            ngx.say("Bar: ", headers["Bar"] or "nil")
        ';
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: bar
Bar: baz
--- log_level: debug
--- no_error_log
lua exceeding request header limit



=== TEST 2: iterating through headers
--- config
    location /req-header {
        content_by_lua '
            local headers, err = ngx.req.get_headers(nil, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            local h = {}
            for k, v in pairs(headers) do
                h[k] = v
            end
            ngx.say("Foo: ", h["Foo"] or "nil")
            ngx.say("Bar: ", h["Bar"] or "nil")
        ';
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: bar
Bar: baz



=== TEST 3: set input header
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Foo", "new value");
        ';

        echo "Foo: $http_foo";
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: new value



=== TEST 4: clear input header
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("Foo", nil);
        ';

        echo "Foo: $http_foo";
    }
--- request
GET /req-header
--- more_headers
Foo: bar
Bar: baz
--- response_body
Foo: 



=== TEST 5: rewrite content length
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("Content-Length", 2048)
        ';
        echo_read_request_body;
        echo_request_body;
    }
--- request eval
"POST /bar\n" .
"a" x 4096
--- response_body eval
"a" x 2048
--- timeout: 15



=== TEST 6: rewrite content length (normalized form)
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("content-length", 2048)
        ';
        echo_read_request_body;
        echo_request_body;
    }
--- request eval
"POST /bar\n" .
"a" x 4096
--- response_body eval
"a" x 2048
--- timeout: 15



=== TEST 7: rewrite host and user-agent
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("Host", "foo")
            ngx.req.set_header("User-Agent", "blah")
        ';
        echo "Host: $host";
        echo "User-Agent: $http_user_agent";
    }
--- request
GET /bar
--- response_body
Host: foo
User-Agent: blah



=== TEST 8: clear host and user-agent
$host always has a default value and cannot be really cleared.
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("Host", nil)
            ngx.req.set_header("User-Agent", nil)
        ';
        echo "Host: $host";
        echo "Host (2): $http_host";
        echo "User-Agent: $http_user_agent";
    }
--- request
GET /bar
--- response_body
Host: localhost
Host (2): 
User-Agent: 



=== TEST 9: clear host and user-agent (the other way)
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.clear_header("Host")
            ngx.req.clear_header("User-Agent")
            ngx.req.clear_header("X-Foo")
        ';
        echo "Host: $host";
        echo "User-Agent: $http_user_agent";
        echo "X-Foo: $http_x_foo";
    }
--- request
GET /bar
--- more_headers
X-Foo: bar
--- response_body
Host: localhost
User-Agent: 
X-Foo: 



=== TEST 10: clear content-length
--- config
    location /bar {
        access_by_lua '
            ngx.req.clear_header("Content-Length")
        ';
        echo "Content-Length: $http_content_length";
    }
--- request
POST /bar
hello
--- more_headers
--- response_body
Content-Length: 



=== TEST 11: rewrite type
--- config
    location /bar {
        access_by_lua '
            ngx.req.set_header("Content-Type", "text/css")
        ';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
Content-Type: text/css



=== TEST 12: clear type
--- config
    location /bar {
        access_by_lua '
            ngx.req.clear_header("Content-Type")
        ';
        echo "Content-Type: $content_type";
    }
--- request
POST /bar
hello
--- more_headers
Content-Type: text/plain
--- response_body
Content-Type: 



=== TEST 13: add multiple request headers
--- config
    location /bar {
        access_by_lua '
            ngx.req.set_header("Foo", {"a", "b"})
        ';
        echo "Foo: $http_foo";
    }
--- request
GET /bar
--- response_body
Foo: a



=== TEST 14: add multiple request headers
--- config
    location /bar {
        access_by_lua '
            ngx.req.set_header("Foo", {"a", "abc"})
        ';
        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        echo $echo_client_request_headers;
    }
--- request
GET /bar
--- response_body_like chomp
\bFoo: a\r\n.*?\bFoo: abc\b



=== TEST 15: set_header and clear_header should refresh ngx.req.get_headers() automatically
--- config
    location /foo {
        content_by_lua '
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("Foo: ", headers["Foo"] or "nil")

            ngx.req.set_header("Foo", 32)

            headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("Foo 1: ", headers["Foo"] or "nil")

            ngx.req.set_header("Foo", "abc")

            headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("Foo 2: ", headers["Foo"] or "nil")

            ngx.req.clear_header("Foo")

            headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("Foo 3: ", headers["Foo"] or "nil")
        ';
    }
--- more_headers
Foo: foo

--- request
    GET /foo
--- response_body
Foo: foo
Foo 1: 32
Foo 2: abc
Foo 3: nil



=== TEST 16: duplicate req headers
--- config
    location /foo {
        content_by_lua '
            collectgarbage()
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            local vals = headers["Foo"]
            ngx.say("value is of type ", type(vals), ".")
            if type(vals) == "table" then
                ngx.say("Foo takes ", #vals or "nil", " values.")
                ngx.say("They are ", table.concat(vals, ", "), ".")
            end
        ';
    }
--- more_headers
Foo: foo
Foo: bar
Foo: baz
--- request
    GET /foo
--- response_body
value is of type table.
Foo takes 3 values.
They are foo, bar, baz.



=== TEST 17: Accept-Encoding (scalar)
--- config
    location /bar {
        default_type 'text/plain';
        rewrite_by_lua '
            ngx.req.set_header("Accept-Encoding", "gzip")
        ';
        gzip on;
        gzip_min_length  1;
        gzip_buffers     4 8k;
        gzip_types       text/plain;
    }
--- user_files
">>> bar
" . ("hello" x 512)
--- request
GET /bar
--- response_headers
Content-Encoding: gzip
--- response_body_like: .{20}



=== TEST 18: Accept-Encoding (table)
--- config
    location /bar {
        default_type 'text/plain';
        rewrite_by_lua '
            ngx.req.set_header("Accept-Encoding", {"gzip"})
        ';
        gzip on;
        gzip_min_length  1;
        gzip_buffers     4 8k;
        gzip_types       text/plain;
    }
--- user_files
">>> bar
" . ("hello" x 512)
--- request
GET /bar
--- response_headers
Content-Encoding: gzip
--- response_body_like: .{20}



=== TEST 19: exceeding default max 100 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(headers) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", headers[key])
            end
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 99) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 98) {
    push @k, "x-$i";
    $i++;
}
push @k, "connection: close\n";
push @k, "host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
"err: truncated\n" . CORE::join("", @k);
--- timeout: 4
--- error_log
lua exceeding request header limit 101 > 100



=== TEST 20: NOT exceeding default max 100 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(headers) do
                table.insert(keys, key)
            end

            table.sort(keys)
            local cnt = 0
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", headers[key])
                cnt = cnt + 1
            end
            ngx.say("found ", cnt, " headers")
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 98) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 98) {
    push @k, "x-$i";
    $i++;
}
push @k, "connection: close\n";
push @k, "host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k) . "found 100 headers\n";
--- timeout: 4
--- no_error_log
[error]
lua exceeding request header limit



=== TEST 21: exceeding custom max 102 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(102)
            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(headers) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", headers[key])
            end
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 101) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 100) {
    push @k, "x-$i";
    $i++;
}
push @k, "connection: close\n";
push @k, "host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
"err: truncated\n" . CORE::join("", @k);
--- timeout: 4
--- error_log
lua exceeding request header limit 103 > 102



=== TEST 22: NOT exceeding custom max 102 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(102)
            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(headers) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", headers[key])
            end
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 100) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 100) {
    push @k, "x-$i";
    $i++;
}
push @k, "connection: close\n";
push @k, "host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4
--- no_error_log
[error]
lua exceeding request header limit



=== TEST 23: custom unlimited headers
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(0)
            if err then
                ngx.say("err: ", err)
            end

            local keys = {}
            for key, val in pairs(headers) do
                table.insert(keys, key)
            end

            table.sort(keys)
            for i, key in ipairs(keys) do
                ngx.say(key, ": ", headers[key])
            end
        ';
    }
--- request
GET /lua
--- more_headers eval
my $s;
my $i = 1;
while ($i <= 105) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 105) {
    push @k, "x-$i";
    $i++;
}
push @k, "connection: close\n";
push @k, "host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4



=== TEST 24: modify subrequest req headers should not affect the parent
--- config
    location = /main {
        rewrite_by_lua '
            local res = ngx.location.capture("/sub")
            print("subrequest: ", res.status)
        ';

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location /sub {
        content_by_lua '
            ngx.req.set_header("foo121", 121)
            ngx.req.set_header("foo122", 122)
            ngx.say("ok")
        ';
    }

    location = /echo {
        #echo $echo_client_request_headers;
        echo "foo121: [$http_foo121]";
        echo "foo122: [$http_foo122]";
    }
--- request
GET /main
--- more_headers
Foo: foo
Bar: bar
Foo1: foo1
Foo2: foo2
Foo3: foo3
Foo4: foo4
Foo5: foo5
Foo6: foo6
Foo7: foo7
Foo8: foo8
Foo9: foo9
Foo10: foo10
Foo11: foo11
Foo12: foo12
Foo13: foo13
Foo14: foo14
Foo15: foo15
Foo16: foo16
Foo17: foo17
Foo18: foo18
Foo19: foo19
Foo20: foo20
--- response_body
Foo: []
Bar: []
--- SKIP



=== TEST 25: clear_header should clear all the instances of the user custom header
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("Foo")
        ';

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo "Foo: [$http_foo]";
        echo "Test-Header: [$http_test_header]";
    }
--- request
GET /t
--- more_headers
Foo: foo
Foo: bah
Test-Header: 1
--- response_body
Foo: []
Test-Header: [1]



=== TEST 26: clear_header should clear all the instances of the builtin header
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("Content-Type")
        ';

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo "Content-Type: [$http_content_type]";
        echo "Test-Header: [$http_test_header]";
        #echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers
Content-Type: foo
Content-Type: bah
Test-Header: 1
--- response_body
Content-Type: []
Test-Header: [1]



=== TEST 27: Converting POST to GET - clearing headers (bug found by Matthieu Tourne, 411 error page)
--- config
    location /t {
        rewrite_by_lua '
            ngx.req.clear_header("Content-Type")
            ngx.req.clear_header("Content-Length")
        ';

        #proxy_pass http://127.0.0.1:8888;
        proxy_pass http://127.0.0.1:$server_port/back;
    }

    location /back {
        echo -n $echo_client_request_headers;
    }
--- request
POST /t
hello world
--- more_headers
Content-Type: application/ocsp-request
Test-Header: 1
--- response_body_like eval
qr/Connection: close\r
Test-Header: 1\r
\r
$/
--- no_error_log
[error]



=== TEST 28: clear_header() does not duplicate subsequent headers (old bug)
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("Foo")
        ';

        proxy_pass http://127.0.0.1:$server_port/echo;
    }

    location = /echo {
        echo $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers
Bah: bah
Foo: foo
Test-Header: 1
Foo1: foo1
Foo2: foo2
Foo3: foo3
Foo4: foo4
Foo5: foo5
Foo6: foo6
Foo7: foo7
Foo8: foo8
Foo9: foo9
Foo10: foo10
Foo11: foo11
Foo12: foo12
Foo13: foo13
Foo14: foo14
Foo15: foo15
Foo16: foo16
Foo17: foo17
Foo18: foo18
Foo19: foo19
Foo20: foo20
Foo21: foo21
Foo22: foo22
--- response_body_like eval
qr/Bah: bah\r
Test-Header: 1\r
Foo1: foo1\r
Foo2: foo2\r
Foo3: foo3\r
Foo4: foo4\r
Foo5: foo5\r
Foo6: foo6\r
Foo7: foo7\r
Foo8: foo8\r
Foo9: foo9\r
Foo10: foo10\r
Foo11: foo11\r
Foo12: foo12\r
Foo13: foo13\r
Foo14: foo14\r
Foo15: foo15\r
Foo16: foo16\r
Foo17: foo17\r
Foo18: foo18\r
Foo19: foo19\r
Foo20: foo20\r
Foo21: foo21\r
Foo22: foo22\r
/



=== TEST 29: iterating through headers (raw form)
--- config
    location /t {
        content_by_lua '
            local h = {}
            local arr = {}
            local headers, err = ngx.req.get_headers(nil, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            for k, v in pairs(headers) do
                h[k] = v
                table.insert(arr, k)
            end
            table.sort(arr)
            for i, k in ipairs(arr) do
                ngx.say(k, ": ", h[k])
            end
        ';
    }
--- request
GET /t
--- more_headers
My-Foo: bar
Bar: baz
--- response_body
Bar: baz
Connection: close
Host: localhost
My-Foo: bar



=== TEST 30: __index metamethod not working for "raw" mode
--- config
    location /t {
        content_by_lua '
            local h, err = ngx.req.get_headers(nil, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("My-Foo-Header: ", h.my_foo_header)
        ';
    }
--- request
GET /t
--- more_headers
My-Foo-Header: Hello World
--- response_body
My-Foo-Header: nil



=== TEST 31: __index metamethod not working for the default mode
--- config
    location /t {
        content_by_lua '
            local h, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("My-Foo-Header: ", h.my_foo_header)
        ';
    }
--- request
GET /t
--- more_headers
My-Foo-Header: Hello World
--- response_body
My-Foo-Header: Hello World



=== TEST 32: clear input header (just more than 20 headers)
--- config
    location = /t {
        rewrite_by_lua 'ngx.req.clear_header("R")';
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo -n $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
Q: q\r
\r
"



=== TEST 33: clear input header (just more than 20 headers, and add more)
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("R")
            for i = 1, 21 do
                ngx.req.set_header("foo-" .. i, i)
            end
        ';
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo -n $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
Q: q\r
foo-1: 1\r
foo-2: 2\r
foo-3: 3\r
foo-4: 4\r
foo-5: 5\r
foo-6: 6\r
foo-7: 7\r
foo-8: 8\r
foo-9: 9\r
foo-10: 10\r
foo-11: 11\r
foo-12: 12\r
foo-13: 13\r
foo-14: 14\r
foo-15: 15\r
foo-16: 16\r
foo-17: 17\r
foo-18: 18\r
foo-19: 19\r
foo-20: 20\r
foo-21: 21\r
\r
"



=== TEST 34: clear input header (just more than 21 headers)
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("R")
            ngx.req.clear_header("Q")
        ';
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo -n $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
\r
"



=== TEST 35: clear input header (just more than 21 headers)
--- config
    location = /t {
        rewrite_by_lua '
            ngx.req.clear_header("R")
            ngx.req.clear_header("Q")
            for i = 1, 21 do
                ngx.req.set_header("foo-" .. i, i)
            end
        ';
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Host foo;
        #proxy_pass http://127.0.0.1:1234/back;
    }

    location = /back {
        echo -n $echo_client_request_headers;
    }
--- request
GET /t
--- more_headers eval
my $s = "User-Agent: curl\nBah: bah\n";

for my $i ('a' .. 'r') {
    $s .= uc($i) . ": " . "$i\n"
}
$s
--- response_body eval
"GET /back HTTP/1.0\r
Host: foo\r
Connection: close\r
User-Agent: curl\r
Bah: bah\r
A: a\r
B: b\r
C: c\r
D: d\r
E: e\r
F: f\r
G: g\r
H: h\r
I: i\r
J: j\r
K: k\r
L: l\r
M: m\r
N: n\r
O: o\r
P: p\r
foo-1: 1\r
foo-2: 2\r
foo-3: 3\r
foo-4: 4\r
foo-5: 5\r
foo-6: 6\r
foo-7: 7\r
foo-8: 8\r
foo-9: 9\r
foo-10: 10\r
foo-11: 11\r
foo-12: 12\r
foo-13: 13\r
foo-14: 14\r
foo-15: 15\r
foo-16: 16\r
foo-17: 17\r
foo-18: 18\r
foo-19: 19\r
foo-20: 20\r
foo-21: 21\r
\r
"



=== TEST 36: raw form
--- config
    location /t {
        content_by_lua '
            local headers, err = ngx.req.get_headers(0, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            -- get ALL the raw headers (0 == no limit, not recommended)
            local h = {}
            local arr = {}
            for k, v in pairs(headers) do
                h[k] = v
                table.insert(arr, k)
            end
            table.sort(arr)
            for i, k in ipairs(arr) do
                ngx.say(k, ": ", h[k])
            end
        ';
    }
--- request
GET /t
--- more_headers
My-Foo: bar
Bar: baz
--- response_body
Bar: baz
Connection: close
Host: localhost
My-Foo: bar
--- no_error_log
[error]



=== TEST 37: clear X-Real-IP
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("X-Real-IP", nil)
        ';
        echo "X-Real-IP: $http_x_real_ip";
    }
--- request
GET /t
--- more_headers
X-Real-IP: 8.8.8.8

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    if (@defined($r->headers_in->x_real_ip) && $r->headers_in->x_real_ip) {
        printf("rewrite: x-real-ip: %s\n",
               user_string_n($r->headers_in->x_real_ip->value->data,
                             $r->headers_in->x_real_ip->value->len))
    } else {
        println("rewrite: no x-real-ip")
    }
}

F(ngx_http_core_content_phase) {
    if (@defined($r->headers_in->x_real_ip) && $r->headers_in->x_real_ip) {
        printf("content: x-real-ip: %s\n",
               user_string_n($r->headers_in->x_real_ip->value->data,
                             $r->headers_in->x_real_ip->value->len))
    } else {
        println("content: no x-real-ip")
    }
}

--- stap_out
rewrite: x-real-ip: 8.8.8.8
content: no x-real-ip

--- response_body
X-Real-IP: 

--- no_error_log
[error]



=== TEST 38: set custom X-Real-IP
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("X-Real-IP", "8.8.4.4")
        ';
        echo "X-Real-IP: $http_x_real_ip";
    }
--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    if (@defined($r->headers_in->x_real_ip) && $r->headers_in->x_real_ip) {
        printf("rewrite: x-real-ip: %s\n",
               user_string_n($r->headers_in->x_real_ip->value->data,
                             $r->headers_in->x_real_ip->value->len))
    } else {
        println("rewrite: no x-real-ip")
    }

}

F(ngx_http_core_content_phase) {
    if (@defined($r->headers_in->x_real_ip) && $r->headers_in->x_real_ip) {
        printf("content: x-real-ip: %s\n",
               user_string_n($r->headers_in->x_real_ip->value->data,
                             $r->headers_in->x_real_ip->value->len))
    } else {
        println("content: no x-real-ip")
    }
}

--- stap_out
rewrite: no x-real-ip
content: x-real-ip: 8.8.4.4

--- response_body
X-Real-IP: 8.8.4.4

--- no_error_log
[error]



=== TEST 39: clear Via
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Via", nil)
        ';
        echo "Via: $http_via";
    }
--- request
GET /t
--- more_headers
Via: 1.0 fred, 1.1 nowhere.com (Apache/1.1)

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    if (@defined($r->headers_in->via) && $r->headers_in->via) {
        printf("rewrite: via: %s\n",
               user_string_n($r->headers_in->via->value->data,
                             $r->headers_in->via->value->len))
    } else {
        println("rewrite: no via")
    }
}

F(ngx_http_core_content_phase) {
    if (@defined($r->headers_in->via) && $r->headers_in->via) {
        printf("content: via: %s\n",
               user_string_n($r->headers_in->via->value->data,
                             $r->headers_in->via->value->len))
    } else {
        println("content: no via")
    }
}

--- stap_out
rewrite: via: 1.0 fred, 1.1 nowhere.com (Apache/1.1)
content: no via

--- response_body
Via: 

--- no_error_log
[error]



=== TEST 40: set custom Via
--- config
    location /t {
        rewrite_by_lua '
           ngx.req.set_header("Via", "1.0 fred, 1.1 nowhere.com (Apache/1.1)")
        ';
        echo "Via: $http_via";
    }
--- request
GET /t

--- stap
F(ngx_http_lua_rewrite_by_chunk) {
    if (@defined($r->headers_in->via) && $r->headers_in->via) {
        printf("rewrite: via: %s\n",
               user_string_n($r->headers_in->via->value->data,
                             $r->headers_in->via->value->len))
    } else {
        println("rewrite: no via")
    }

}

F(ngx_http_core_content_phase) {
    if (@defined($r->headers_in->via) && $r->headers_in->via) {
        printf("content: via: %s\n",
               user_string_n($r->headers_in->via->value->data,
                             $r->headers_in->via->value->len))
    } else {
        println("content: no via")
    }
}

--- stap_out
rewrite: no via
content: via: 1.0 fred, 1.1 nowhere.com (Apache/1.1)

--- response_body
Via: 1.0 fred, 1.1 nowhere.com (Apache/1.1)

--- no_error_log
[error]



=== TEST 41: set input header (with underscores in the header name)
--- config
    location /req-header {
        rewrite_by_lua '
            ngx.req.set_header("foo_bar", "some value");
        ';
        proxy_pass http://127.0.0.1:$server_port/back;
    }
    location = /back {
        echo -n $echo_client_request_headers;
    }
--- request
GET /req-header
--- response_body_like eval
qr{^GET /back HTTP/1.0\r
Host: 127.0.0.1:\d+\r
Connection: close\r
foo_bar: some value\r
\r
$}



=== TEST 42: HTTP 0.9 (set & get)
--- config
    location /foo {
        content_by_lua '
            ngx.req.set_header("X-Foo", "howdy");
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("X-Foo: ", headers["X-Foo"])
        ';
    }
--- raw_request eval
"GET /foo\r\n"
--- response_headers
! X-Foo
--- response_body
X-Foo: nil
--- http09
--- no_error_log
[error]



=== TEST 43: HTTP 0.9 (clear)
--- config
    location /foo {
        content_by_lua '
            ngx.req.set_header("X-Foo", "howdy");
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say("X-Foo: ", headers["X-Foo"])
        ';
    }
--- raw_request eval
"GET /foo\r\n"
--- response_headers
! X-Foo
--- response_body
X-Foo: nil
--- http09
--- no_error_log
[error]



=== TEST 44: Host header with port and $host (github issue #292)
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("Host", "agentzh.org:1984")
        ';
        echo "host var: $host";
        echo "http_host var: $http_host";
    }
--- request
GET /bar
--- response_body
host var: agentzh.org
http_host var: agentzh.org:1984



=== TEST 45: Host header with upper case letters and $host (github issue #292)
--- config
    location /bar {
        rewrite_by_lua '
            ngx.req.set_header("Host", "agentZH.org:1984")
        ';
        echo "host var: $host";
        echo "http_host var: $http_host";
    }
--- request
GET /bar
--- response_body
host var: agentzh.org
http_host var: agentZH.org:1984



=== TEST 46: clear all and re-insert
--- config
    location = /t {
        content_by_lua '
            local headers, err = ngx.req.get_headers(100, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            local n = 0
            for header, _ in pairs(headers) do
                n = n + 1
                ngx.req.clear_header(header)
            end
            ngx.say("got ", n, " headers")
            local i = 0
            for header, value in pairs(headers) do
                i = i + 1
                print("1: reinsert header ", header, ": ", i)
                ngx.req.set_header(header, value)
            end

            headers, err = ngx.req.get_headers(100, true)
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            n = 0
            for header, _ in pairs(headers) do
                n = n + 1
                ngx.req.clear_header(header)
            end
            ngx.say("got ", n, " headers")
            -- do return end
            local i = 0
            for header, value in pairs(headers) do
                i = i + 1
                if i > 8 then
                    break
                end
                print("2: reinsert header ", header, ": ", i)
                ngx.req.set_header(header, value)
            end
        ';
    }

--- raw_request eval
"GET /t HTTP/1.1\r
Host: localhost\r
Connection: close\r
Cache-Control: max-age=0\r
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8\r
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/30.0.1599.101 Safari/537.36\r
Accept-Encoding: gzip,deflate,sdch\r
Accept-Language: en-US,en;q=0.8\r
Cookie: test=cookie;\r
\r
"
--- response_body
got 8 headers
got 8 headers
--- no_error_log
[error]



=== TEST 47: github issue #314: ngx.req.set_header does not override request headers with multiple values
--- config
    #lua_code_cache off;
    location = /t {
        content_by_lua '
            ngx.req.set_header("AAA", "111")
            local headers, err = ngx.req.get_headers()
            if err then
                ngx.log(ngx.ERR, "err: ", err)
                return ngx.exit(500)
            end

            ngx.say(headers["AAA"])
        ';
    }
--- request
GET /t
--- more_headers
AAA: 123
AAA: 456
AAA: 678

--- response_body
111
--- no_error_log
[error]



=== TEST 48: clear If-Match req header
--- config
    location /t {
        content_by_lua '
            ngx.req.clear_header("if-match")
            if not ngx.send_headers() then
                return
            end
            ngx.say("test")
        ';
    }
--- request
GET /t
--- more_headers
If-Match: abc
--- response_body
test
--- no_error_log
[error]



=== TEST 49: clear If-Unmodified-Since req header
--- config
    location /t {
        content_by_lua '
            ngx.req.clear_header("if-unmodified-since")
            ngx.header["Last-Modified"] = "Tue, 30 Jun 2011 12:16:36 GMT"
            if not ngx.send_headers() then
                return
            end
            ngx.say("test")
        ';
    }
--- request
GET /t
--- more_headers
If-Unmodified-Since: Tue, 28 Jun 2011 12:16:36 GMT
--- response_body
test
--- no_error_log
[error]



=== TEST 50: clear If-None-Match req header
--- config
    location /t {
        content_by_lua '
            ngx.req.clear_header("if-none-match")
            -- ngx.header["etags"] = "abc"
            if not ngx.send_headers() then
                return
            end
            ngx.say("test")
        ';
    }
--- request
GET /t
--- more_headers
If-None-Match: *
--- response_body
test
--- no_error_log
[error]



=== TEST 51: set the Destination request header for WebDav
--- config
    location = /a.txt {
        rewrite_by_lua_block {
            ngx.req.set_header("Destination", "/b.txt")
        }
        dav_methods MOVE;
        dav_access            all:rw;
        root                  html;
    }

--- user_files
>>> a.txt
hello, world!

--- request
MOVE /a.txt

--- response_body
--- no_error_log
client sent no "Destination" header
[error]
--- error_code: 204



=== TEST 52: X-Forwarded-For
--- config
    location = /t {
        access_by_lua_block {
            ngx.req.set_header("X-Forwarded-For", "8.8.8.8")
        }
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Foo $proxy_add_x_forwarded_for;
    }

    location = /back {
        echo "Foo: $http_foo";
    }

--- request
GET /t

--- response_body
Foo: 8.8.8.8, 127.0.0.1
--- no_error_log
[error]



=== TEST 53: X-Forwarded-For
--- config
    location = /t {
        access_by_lua_block {
            ngx.req.clear_header("X-Forwarded-For")
        }
        proxy_pass http://127.0.0.1:$server_port/back;
        proxy_set_header Foo $proxy_add_x_forwarded_for;
    }

    location = /back {
        echo "Foo: $http_foo";
    }

--- request
GET /t

--- more_headers
X-Forwarded-For: 8.8.8.8
--- response_body
Foo: 127.0.0.1
--- no_error_log
[error]



=== TEST 54: for bad requests (bad request method letter case)
--- config
    error_page 400 = /err;

    location = /err {
        content_by_lua_block {
            ngx.req.set_header("Foo", "bar")
            ngx.say("ok")
        }
    }
--- raw_request
GeT / HTTP/1.1
--- response_body
ok
--- no_error_log
[error]
--- no_check_leak



=== TEST 55: for bad requests (bad request method names)
--- config
    error_page 400 = /err;

    location = /err {
        content_by_lua_block {
            ngx.req.set_header("Foo", "bar")
            ngx.say("ok")
        }
    }
--- raw_request
GET x HTTP/1.1
--- response_body
ok
--- no_error_log
[error]
--- no_check_leak



=== TEST 56: for bad requests causing segfaults when setting & getting multi-value headers
--- config
    error_page 400 = /err;

    location = /err {
        content_by_lua_block {
            ngx.req.set_header("Cookie", "foo=bar")
            local test = ngx.var.cookie_bar

            ngx.say("ok")
        }
    }
--- raw_request
GeT / HTTP/1.1
--- response_body
ok
--- no_error_log
[error]
--- no_check_leak



=== TEST 57: exceeding custom 3 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(3)
            if err then
                ngx.say("err: ", err)
            end

            local cnt = 0
            for key, val in pairs(headers) do
                cnt = cnt + 1
            end

            ngx.say("found ", cnt, " headers.");
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 2) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body
err: truncated
found 3 headers.
--- timeout: 4
--- error_log
lua exceeding request header limit 4 > 3
--- no_error_log
[error]



=== TEST 58: NOT exceeding custom 3 header limit
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(3)
            if err then
                ngx.say("err: ", err)
            end

            local cnt = 0
            for key, val in pairs(headers) do
                cnt = cnt + 1
            end

            ngx.say("found ", cnt, " headers.");
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 1) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body
found 3 headers.
--- timeout: 4
--- no_error_log
lua exceeding request header limit
[error]



=== TEST 59: exceeding custom 3 header limit (raw)
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(3, true)
            if err then
                ngx.say("err: ", err)
            end

            local cnt = 0
            for key, val in pairs(headers) do
                cnt = cnt + 1
            end

            ngx.say("found ", cnt, " headers.");
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 2) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body
err: truncated
found 3 headers.
--- timeout: 4
--- error_log
lua exceeding request header limit 4 > 3
--- no_error_log
[error]



=== TEST 60: NOT exceeding custom 3 header limit (raw)
--- config
    location /lua {
        content_by_lua '
            local headers, err = ngx.req.get_headers(3, true)
            if err then
                ngx.say("err: ", err)
            end

            local cnt = 0
            for key, val in pairs(headers) do
                cnt = cnt + 1
            end

            ngx.say("found ", cnt, " headers.");
        ';
    }
--- request
GET /lua
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 1) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body
found 3 headers.
--- timeout: 4
--- no_error_log
lua exceeding request header limit
[error]



=== TEST 61: setting Host header clears cached $host variable
--- config
    location /req-header {
        # this makes $host indexed and cacheable
        set $foo $host;

        content_by_lua_block {
            ngx.say(ngx.var.host)
            ngx.req.set_header("Host", "new");
            ngx.say(ngx.var.host)
        }
    }
--- request
GET /req-header
--- response_body
localhost
new
--- no_error_log
[error]



=== TEST 62: unsafe header name (with '\r')
--- config
    location /req-header {
        rewrite_by_lua_block {
            ngx.req.set_header("Foo\rfoo", "new value");
        }

        echo "Foo: $http_foo";
    }
--- request
GET /req-header
--- response_body
Foo: 
--- no_error_log
[error]



=== TEST 63: unsafe header value (with '\n')
--- config
    location /req-header {
        rewrite_by_lua_block {
            ngx.req.set_header("Foo", "new\nvalue");
        }

        echo "Foo: $http_foo";
    }
--- request
GET /req-header
--- response_body
Foo: new%0Avalue
--- no_error_log
[error]



=== TEST 64: multiple unsafe header values (with '\n' and '\t')
--- config
    location /req-header {
        rewrite_by_lua_block {
            ngx.req.set_header("Foo", { "new\nvalue", "foo\tbar" } );
        }

        content_by_lua_block {
            ngx.say(table.concat(ngx.req.get_headers()["foo"], ", "), ".")
        }
    }
--- request
GET /req-header
--- response_body
new%0Avalue, foo	bar.
--- no_error_log
[error]



=== TEST 65: unsafe names/values logging escapes '"' and '\' characters
--- config
    location /req-header {
        rewrite_by_lua_block {
            ngx.req.set_header("Foo", "\"new\nvalue\\\"");
        }

        content_by_lua_block {
            ngx.say(ngx.req.get_headers()["foo"])
        }
    }
--- request
GET /req-header
--- response_body
"new%0Avalue\"
--- no_error_log
[error]



=== TEST 66: add request headers with '\r\n'
--- config
    location /bar {
        access_by_lua_block {
            ngx.req.set_header("Foo\r", "123\r\n")
        }
        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        echo $echo_client_request_headers;
    }
--- request
GET /bar
--- response_body_like chomp
\bFoo%0D: 123%0D%0A\b



=== TEST 67: add request headers with '\0'
--- config
    location /bar {
        access_by_lua_block {
            ngx.req.set_header("Foo", "\0")
        }
        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        echo $echo_client_request_headers;
    }
--- request
GET /bar
--- response_body_like chomp
\bFoo: %00\b



=== TEST 68: add request headers with '中文'
--- config
    location /bar {
        access_by_lua_block {
            ngx.req.set_header("Foo中文", "ab中文a")
        }
        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        echo $echo_client_request_headers;
    }
--- request
GET /bar
--- response_body_like chomp
\bFoo%E4%B8%AD%E6%96%87: ab中文a\r\n
