# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
log_level('debug');

repeat_each(3);

plan tests => repeat_each() * (blocks() * 2 + 23);

our $HtmlDir = html_dir;
#warn $html_dir;

#no_diff();
#no_long_string();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;

#no_shuffle();
no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- http_config eval
    "lua_package_path '$::HtmlDir/?.lua;./?.lua';"
--- config
    location /load {
        content_by_lua '
            package.loaded.foo = nil;
            local foo = require "foo";
            foo.hi()
        ';
    }
--- request
GET /load
--- user_files
>>> foo.lua
module(..., package.seeall);

function foo () 
    return 1
    return 2
end
--- error_code: 500
--- response_body_like: 500 Internal Server Error



=== TEST 2: sanity
--- http_config
lua_package_path '/home/agentz/rpm/BUILD/lua-yajl-1.1/build/?.so;/home/lz/luax/?.so;./?.so';
--- config
    location = '/report/listBidwordPrices4lzExtra.htm' {
        content_by_lua '
            local yajl = require "yajl"
            local w = ngx.var.arg_words
            w = ngx.unescape_uri(w)
            local r = {}
            print("start for")
            for id in string.gmatch(w, "%d+") do
                 r[id] = -1
            end
            print("end for, start yajl")
            ngx.print(yajl.to_string(r))
            print("end yajl")
        ';
    }
--- request
GET /report/listBidwordPrices4lzExtra.htm?words=123,156,2532
--- response_body
--- SKIP



=== TEST 3: sanity
--- config
    location = /memc {
        #set $memc_value 'hello';
        set $memc_value $arg_v;
        set $memc_cmd $arg_c;
        set $memc_key $arg_k;
        #set $memc_value hello;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        #echo $memc_value;
    }
    location = /echo {
        echo_location '/memc?c=get&k=foo';
        echo_location '/memc?c=set&k=foo&v=hello';
        echo_location '/memc?c=get&k=foo';
    }
    location = /main {
        content_by_lua '
            res = ngx.location.capture("/memc?c=get&k=foo&v=")
            ngx.say("1: ", res.body)

            res = ngx.location.capture("/memc?c=set&k=foo&v=bar");
            ngx.say("2: ", res.body);

            res = ngx.location.capture("/memc?c=get&k=foo")
            ngx.say("3: ", res.body);
        ';
    }
--- request
GET /main
--- response_body_like: 3: bar$



=== TEST 4: capture works for subrequests with internal redirects
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/")
            ngx.say(res.status)
            ngx.print(res.body)
        ';
    }
--- request
    GET /lua
--- response_body_like chop
200
.*It works
--- SKIP



=== TEST 5: disk file bufs not working
--- config
    location /lua {
        content_by_lua '
            local res = ngx.location.capture("/test.lua")
            ngx.say(res.status)
            ngx.print(res.body)
        ';
    }
--- user_files
>>> test.lua
print("Hello, world")
--- request
    GET /lua
--- response_body
200
print("Hello, world")



=== TEST 6: print lua empty strings
--- config
    location /lua {
        content_by_lua 'ngx.print("") ngx.flush() ngx.print("Hi")';
    }
--- request
GET /lua
--- response_body chop
Hi



=== TEST 7: say lua empty strings
--- config
    location /lua {
        content_by_lua 'ngx.say("") ngx.flush() ngx.print("Hi")';
    }
--- request
GET /lua
--- response_body eval
"
Hi"



=== TEST 8: github issue 37: header bug
https://github.com/chaoslawful/lua-nginx-module/issues/37
--- config
    location /sub {
        content_by_lua '
            ngx.header["Set-Cookie"] = {"TestCookie1=foo", "TestCookie2=bar"};
            ngx.say("Hello")
        ';
    }
    location /lua {
        content_by_lua '
            -- local yajl = require "yajl"
            ngx.header["Set-Cookie"] = {}
            res = ngx.location.capture("/sub")

            for i,j in pairs(res.header) do
                ngx.header[i] = j
            end

            -- ngx.say("set-cookie: ", yajl.to_string(res.header["Set-Cookie"]))

            ngx.send_headers()
            ngx.print("body: ", res.body)
        ';
    }
--- request
GET /lua
--- raw_response_headers_like eval
".*Set-Cookie: TestCookie1=foo\r
Set-Cookie: TestCookie2=bar.*"



=== TEST 9: memory leak
--- config
    location /foo {
        content_by_lua_file 'html/foo.lua';
    }
--- user_files
>>> foo.lua
res = {}
res = {'good 1', 'good 2', 'good 3'}
return ngx.redirect("/somedir/" .. ngx.escape_uri(res[math.random(1,#res)]))
--- request
    GET /foo
--- response_body
--- SKIP



=== TEST 10: capturing locations with internal redirects (no lua redirect)
--- config
    location /bar {
        echo Bar;
    }
    location /foo {
        #content_by_lua '
        #ngx.exec("/bar")
        #';
        echo_exec /bar;
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo")
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body
Bar



=== TEST 11: capturing locations with internal redirects (lua redirect)
--- config
    location /bar {
        content_by_lua 'ngx.say("Bar")';
    }
    location /foo {
        content_by_lua '
            ngx.exec("/bar")
        ';
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo")
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body
Bar



=== TEST 12: capturing locations with internal redirects (simple index)
--- config
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/")
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body chop
<html><head><title>It works!</title></head><body>It works!</body></html>



=== TEST 13: capturing locations with internal redirects (more lua statements)
--- config
    location /bar {
        content_by_lua '
            ngx.say("hello")
            ngx.say("world")
        ';
    }
    location /foo {
        #content_by_lua '
        #ngx.exec("/bar")
        #';
        echo_exec /bar;
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo")
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body
hello
world



=== TEST 14: capturing locations with internal redirects (post subrequest with internal redirect)
--- config
    location /bar {
        lua_need_request_body on;
        client_body_in_single_buffer on;

        content_by_lua '
            ngx.say(ngx.var.request_body)
        ';
    }
    location /foo {
        #content_by_lua '
        #ngx.exec("/bar")
        #';
        echo_exec /bar;
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo", { method = ngx.HTTP_POST, body = "hello" })
            ngx.print(res.body)
        ';
    }
--- request
    GET /main
--- response_body
hello



=== TEST 15: nginx rewrite works in subrequests
--- config
    rewrite /foo /foo/ permanent;
    location = /foo/ {
        echo hello;
    }
    location /main {
        content_by_lua '
            local res = ngx.location.capture("/foo")
            ngx.say("status = ", res.status)
            ngx.say("Location: ", res.header["Location"] or "nil")
        ';
    }
--- request
    GET /main
--- response_body
status = 301
Location: /foo/



=== TEST 16: nginx rewrite works in subrequests
--- config
    access_by_lua '
        local res = ngx.location.capture(ngx.var.uri)
        ngx.say("status = ", res.status)
        ngx.say("Location: ", res.header["Location"] or "nil")
        ngx.exit(200)
    ';
--- request
    GET /foo
--- user_files
>>> foo/index.html
It works!
--- response_body
status = 301
Location: /foo/



=== TEST 17: set content-type header with charset
--- config
    location /lua {
        charset GBK;
        content_by_lua '
            ngx.header.content_type = "text/xml; charset=UTF-8"
            ngx.say("hi")
        ';
    }
--- request
    GET /lua
--- response_body
hi
--- response_headers
Content-Type: text/xml; charset=UTF-8



=== TEST 18: set response header content-type with charset
--- config
    location /lua {
        charset GBK;
        content_by_lua '
            ngx.header.content_type = "text/xml"
            ngx.say("hi")
        ';
    }
--- request
    GET /lua
--- response_body
hi
--- response_headers
Content-Type: text/xml; charset=GBK



=== TEST 19: get by-position capturing variables
--- config
    location ~ '^/lua/(.*)' {
        content_by_lua '
            ngx.say(ngx.var[1] or "nil")
        ';
    }
--- request
    GET /lua/hello
--- response_body
hello



=== TEST 20: get by-position capturing variables ($0)
--- config
    location ~ '^/lua/(.*)' {
        content_by_lua '
            ngx.say(ngx.var[0] or "nil")
        ';
    }
--- request
    GET /lua/hello
--- response_body
nil



=== TEST 21: get by-position capturing variables (exceeding captures)
--- config
    location ~ '^/lua/(.*)' {
        content_by_lua '
            ngx.say(ngx.var[2] or "nil")
        ';
    }
--- request
    GET /lua/hello
--- response_body
nil



=== TEST 22: get by-position capturing variables ($1, $2)
--- config
    location ~ '^/lua/(.*)/(.*)' {
        content_by_lua '
            ngx.say(ngx.var[-1] or "nil")
            ngx.say(ngx.var[0] or "nil")
            ngx.say(ngx.var[1] or "nil")
            ngx.say(ngx.var[2] or "nil")
            ngx.say(ngx.var[3] or "nil")
            ngx.say(ngx.var[4] or "nil")
        ';
    }
--- request
    GET /lua/hello/world
--- response_body
nil
nil
hello
world
nil
nil



=== TEST 23: set special variables
--- config
    location /main {
        #set_unescape_uri $cookie_a "hello";
        set $http_a "hello";
        content_by_lua '
            ngx.say(ngx.var.http_a)
        ';
    }
--- request
    GET /main
--- response_body
hello
--- SKIP



=== TEST 24: set special variables
--- config
    location /main {
        content_by_lua '
            dofile(ngx.var.realpath_root .. "/a.lua")
        ';
    }
    location /echo {
        echo hi;
    }
--- request
    GET /main
--- user_files
>>> a.lua
ngx.location.capture("/echo")
--- response_body
--- SKIP



=== TEST 25: set 20+ headers
--- config
    location /test {
        rewrite_by_lua '
            ngx.req.clear_header("Authorization")
        ';
        echo $http_a1;
        echo $http_authorization;
        echo $http_a2;
        echo $http_a3;
        echo $http_a23;
        echo $http_a24;
        echo $http_a25;
    }
--- request
    GET /test
--- more_headers eval
my $i = 1;
my $s;
while ($i <= 25) {
    $s .= "A$i: $i\n";
    if ($i == 22) {
        $s .= "Authorization: blah\n";
    }
    $i++;
}
#warn $s;
$s
--- response_body
1

2
3
23
24
25



=== TEST 26: unexpected globals sharing by using _G
--- config
    location /test {
        content_by_lua '
            if _G.t then
                _G.t = _G.t + 1
            else
                _G.t = 0
            end
            ngx.print(t)
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test", "GET /test"]
--- response_body eval
["0", "0", "0"]



=== TEST 27: unexpected globals sharing by using _G (set_by_lua*)
--- config
    location /test {
        set_by_lua $a '
            if _G.t then
                _G.t = _G.t + 1
            else
                _G.t = 0
            end
            return t
        ';
        echo -n $a;
    }
--- pipelined_requests eval
["GET /test", "GET /test", "GET /test"]
--- response_body eval
["0", "0", "0"]



=== TEST 28: unexpected globals sharing by using _G (log_by_lua*)
--- http_config
    lua_shared_dict log_dict 100k;
--- config
    location /test {
        content_by_lua '
            local log_dict = ngx.shared.log_dict
            ngx.print(log_dict:get("cnt") or 0)
        ';

        log_by_lua '
            local log_dict = ngx.shared.log_dict
            if _G.t then
                _G.t = _G.t + 1
            else
                _G.t = 0
            end
            log_dict:set("cnt", t)
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test", "GET /test"]
--- response_body eval
["0", "0", "0"]



=== TEST 29: unexpected globals sharing by using _G (header_filter_by_lua*)
--- config
    location /test {
        header_filter_by_lua '
            if _G.t then
                _G.t = _G.t + 1
            else
                _G.t = 0
            end
            ngx.ctx.cnt = tostring(t)
        ';
        content_by_lua '
            ngx.send_headers()
            ngx.print(ngx.ctx.cnt or 0)
        ';
    }
--- pipelined_requests eval
["GET /test", "GET /test", "GET /test"]
--- response_body eval
["0", "0", "0"]



=== TEST 30: unexpected globals sharing by using _G (body_filter_by_lua*)
--- config
    location /test {
        body_filter_by_lua '
            if _G.t then
                _G.t = _G.t + 1
            else
                _G.t = 0
            end
            ngx.ctx.cnt = _G.t
        ';
        content_by_lua '
            ngx.print("a")
            ngx.say(ngx.ctx.cnt or 0)
        ';
    }
--- request
GET /test
--- response_body
a0
--- no_error_log
[error]



=== TEST 31: set content-type header with charset and default_type
--- http_config
--- config
    location /lua {
        default_type application/json;
        charset utf-8;
        charset_types application/json;
        content_by_lua 'ngx.say("hi")';
    }
--- request
    GET /lua
--- response_body
hi
--- response_headers
Content-Type: application/json; charset=utf-8



=== TEST 32: hang on upstream_next (from kindy)
--- http_config
    upstream xx {
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
        server 127.0.0.1:$TEST_NGINX_SERVER_PORT;
    }

    server {
        server_name "xx";
        listen $TEST_NGINX_SERVER_PORT;

        return 444;
    }
--- config
    location = /t {
        proxy_pass http://xx;
    }

    location = /bad {
        return 444;
    }
--- request
    GET /t
--- timeout: 1
--- response_body_like: 502 Bad Gateway
--- error_code: 502
--- error_log
upstream prematurely closed connection while reading response header from upstream



=== TEST 33: last_in_chain is set properly in subrequests
--- config
    location = /sub {
        echo hello;
        body_filter_by_lua '
            local eof = ngx.arg[2]
            if eof then
                print("eof found in body stream")
            end
        ';
    }

    location = /main {
        echo_location /sub;
    }

--- request
    GET /main
--- response_body
hello
--- log_level: notice
--- error_log
eof found in body stream



=== TEST 34: testing a segfault when using ngx_poll_module + ngx_resolver
See more details here: http://mailman.nginx.org/pipermail/nginx-devel/2013-January/003275.html
--- config
    location /t {
        set $myserver nginx.org;
        proxy_pass http://$myserver/;
        resolver 127.0.0.1;
    }
--- request
    GET /t
--- ignore_response
--- abort
--- timeout: 0.3
--- log_level: notice
--- no_error_log
[alert]
--- error_log eval
qr/recv\(\) failed \(\d+: Connection refused\) while resolving/



=== TEST 35: github issue #218: ngx.location.capture hangs when querying a remote host that does not exist or is really slow to respond
--- config
    set $myurl "https://not-exist.agentzh.org";
    location /toto {
        content_by_lua '
                local proxyUrl = "/myproxy/entity"
                local res = ngx.location.capture( proxyUrl,  { method = ngx.HTTP_GET })
                ngx.say("Hello, ", res.status)
            ';
    }
    location ~ /myproxy {

        rewrite    ^/myproxy/(.*)  /$1  break;
        resolver_timeout 1s;
        #resolver 172.16.0.23; #  AWS DNS resolver address is the same in all regions - 172.16.0.23
        resolver 8.8.8.8;
        proxy_read_timeout 1s;
        proxy_send_timeout 1s;
        proxy_connect_timeout 1s;
        proxy_pass $myurl:443;
        proxy_pass_request_body off;
        proxy_set_header Content-Length 0;
        proxy_set_header  Accept-Encoding  "";
    }

--- request
GET /toto

--- stap2
F(ngx_http_lua_post_subrequest) {
    println("lua post subrequest")
    print_ubacktrace()
}

--- response_body
Hello, 502

--- error_log
not-exist.agentzh.org could not be resolved
--- timeout: 3

