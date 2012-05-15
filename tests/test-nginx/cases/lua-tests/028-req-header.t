# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => (2 * blocks() + 4) * repeat_each();

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: random access req headers
--- config
    location /req-header {
        content_by_lua '
            ngx.say("Foo: ", ngx.req.get_headers()["Foo"] or "nil")
            ngx.say("Bar: ", ngx.req.get_headers()["Bar"] or "nil")
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



=== TEST 2: iterating through headers
--- config
    location /req-header {
        content_by_lua '
            local h = {}
            for k, v in pairs(ngx.req.get_headers()) do
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
            ngx.req.set_header("content_length", 2048)
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
            ngx.say("Foo: ", ngx.req.get_headers()["Foo"] or "nil")

            ngx.req.set_header("Foo", 32)
            ngx.say("Foo 1: ", ngx.req.get_headers()["Foo"] or "nil")

            ngx.req.set_header("Foo", "abc")
            ngx.say("Foo 2: ", ngx.req.get_headers()["Foo"] or "nil")

            ngx.req.clear_header("Foo")
            ngx.say("Foo 3: ", ngx.req.get_headers()["Foo"] or "nil")
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
            local vals = ngx.req.get_headers()["Foo"]
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



=== TEST 19: default max 100 headers
--- config
    location /lua {
        content_by_lua '
            local headers = ngx.req.get_headers()
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
while ($i <= 102) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 98) {
    push @k, "X-$i";
    $i++;
}
push @k, "Connection: Close\n";
push @k, "Host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4
--- error_log
lua hit request header limit 100



=== TEST 20: custom max 102 headers
--- config
    location /lua {
        content_by_lua '
            local headers = ngx.req.get_headers(102)
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
while ($i <= 103) {
    $s .= "X-$i:$i\n";
    $i++;
}
$s
--- response_body eval
my @k;
my $i = 1;
while ($i <= 100) {
    push @k, "X-$i";
    $i++;
}
push @k, "Connection: Close\n";
push @k, "Host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4
--- error_log
lua hit request header limit 102



=== TEST 21: custom unlimited headers
--- config
    location /lua {
        content_by_lua '
            local headers = ngx.req.get_headers(0)
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
    push @k, "X-$i";
    $i++;
}
push @k, "Connection: Close\n";
push @k, "Host: localhost\n";
@k = sort @k;
for my $k (@k) {
    if ($k =~ /\d+/) {
        $k .= ": $&\n";
    }
}
CORE::join("", @k);
--- timeout: 4

