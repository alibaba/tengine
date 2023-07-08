# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

#repeat_each(20000);
#repeat_each(200);
repeat_each(2);
#master_on();
#workers(1);
#log_level('debug');
#log_level('warn');
#worker_connections(1024);

plan tests => repeat_each() * (blocks() * 3 + 2);

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

our $LuaCpath = $ENV{LUA_CPATH} ||
    '/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;';

#$ENV{LUA_PATH} = $ENV{HOME} . '/work/JSON4Lua-0.9.30/json/?.lua';

no_long_string();

run_tests();

__DATA__

=== TEST 1: throw 403
--- config
    location /lua {
        content_by_lua "ngx.exit(403);ngx.say('hi')";
    }
--- request
GET /lua
--- error_code: 403
--- response_body_like: 403 Forbidden
--- no_error_log
[error]



=== TEST 2: throw 404
--- config
    location /lua {
        content_by_lua "ngx.exit(404);ngx.say('hi');";
    }
--- request
GET /lua
--- error_code: 404
--- response_body_like: 404 Not Found
--- no_error_log
[error]



=== TEST 3: throw 404 after sending the header and partial body
--- config
    location /lua {
        content_by_lua "ngx.say('hi');ngx.exit(404);ngx.say(', you')";
    }
--- request
GET /lua
--- error_log
attempt to set status 404 via ngx.exit after sending out the response status 200
--- no_error_log
alert
--- response_body
hi



=== TEST 4: working with ngx_auth_request (succeeded)
--- config
    location /auth {
        content_by_lua "
            if ngx.var.user == 'agentzh' then
                ngx.eof();
            else
                ngx.exit(403)
            end";
    }
    location /api {
        set $user $arg_user;
        auth_request /auth;

        echo "Logged in";
    }
--- request
GET /api?user=agentzh
--- error_code: 200
--- response_body
Logged in
--- no_error_log
[error]



=== TEST 5: working with ngx_auth_request (failed)
--- config
    location /auth {
        content_by_lua "
            if ngx.var.user == 'agentzh' then
                ngx.eof();
            else
                ngx.exit(403)
            end";
    }
    location /api {
        set $user $arg_user;
        auth_request /auth;

        echo "Logged in";
    }
--- request
GET /api?user=agentz
--- error_code: 403
--- response_body_like: 403 Forbidden
--- no_error_log
[error]



=== TEST 6: working with ngx_auth_request (simplest form, w/o ngx_memc)
--- http_config eval
"
    lua_package_cpath '$::LuaCpath';
    upstream backend {
        drizzle_server 127.0.0.1:\$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }
"
--- config
    location /memc {
        internal;

        set $memc_key $arg_key;
        set $memc_exptime $arg_exptime;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /conv-uid-mysql {
        internal;

        set $key "conv-uid-$arg_uid";

        #srcache_fetch GET /memc key=$key;
        #srcache_store PUT /memc key=$key;

        default_type 'application/json';

        drizzle_query "select new_uid as uid from conv_uid where old_uid=$arg_uid";
        drizzle_pass backend;

        rds_json on;
    }

    location /conv-uid {
        internal;
        content_by_lua_file 'html/foo.lua';
    }
    location /api {
        set $uid $arg_uid;
        auth_request /conv-uid;

        echo "Logged in $uid";
    }
--- user_files
>>> foo.lua
local cjson = require('cjson');
local old_uid = ngx.var.uid
-- print('about to run sr')
local res = ngx.location.capture('/conv-uid-mysql?uid=' .. old_uid)
if (res.status ~= ngx.HTTP_OK) then
    ngx.exit(res.status)
end
-- print('just have run sr: ' .. res.body)
res = cjson.decode(res.body)
if (not res or not res[1] or not res[1].uid or
        not string.match(res[1].uid, '^%d+$')) then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.var.uid = res[1].uid;
-- print('done')
--- request
GET /api?uid=32
--- response_body
Logged in 56
--- no_error_log
[error]



=== TEST 7: working with ngx_auth_request (simplest form)
--- http_config eval
"
    lua_package_cpath '$::LuaCpath';
    upstream backend {
        drizzle_server 127.0.0.1:\$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }
"
--- config
    location /memc {
        internal;

        set $memc_key $arg_key;
        set $memc_exptime $arg_exptime;

        memc_pass 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
    }

    location /conv-uid-mysql {
        internal;

        set $key "conv-uid-$arg_uid";

        #srcache_fetch GET /memc key=$key;
        #srcache_store PUT /memc key=$key;

        default_type 'application/json';

        drizzle_query "select new_uid as uid from conv_uid where old_uid=$arg_uid";
        drizzle_pass backend;

        rds_json on;
    }

    location /conv-uid {
        internal;
        content_by_lua_file 'html/foo.lua';
    }
    location /api {
        set $uid $arg_uid;
        auth_request /conv-uid;

        echo "Logged in $uid";
    }
--- user_files
>>> foo.lua
local cjson = require('cjson');
local old_uid = ngx.var.uid
-- print('about to run sr')
local res = ngx.location.capture('/conv-uid-mysql?uid=' .. old_uid)
-- print('just have run sr' .. res.body)
if (res.status ~= ngx.HTTP_OK) then
    ngx.exit(res.status)
end
res = cjson.decode(res.body)
if (not res or not res[1] or not res[1].uid or
        not string.match(res[1].uid, '^%d+$')) then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.var.uid = res[1].uid;
-- print('done')
--- request
GET /api?uid=32
--- response_body
Logged in 56
--- no_error_log
[error]



=== TEST 8: working with ngx_auth_request
--- http_config eval
"
    lua_package_cpath '$::LuaCpath';
    upstream backend {
        drizzle_server 127.0.0.1:\$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }

    upstream memc_a {
        server 127.0.0.1:\$TEST_NGINX_MEMCACHED_PORT;
    }

    upstream memc_b {
        server 127.0.0.1:\$TEST_NGINX_MEMCACHED_PORT;
    }

    upstream_list memc_cluster memc_a memc_b;
"
--- config
    location /memc {
        internal;

        set $memc_key $arg_key;
        set $memc_exptime $arg_exptime;

        set_hashed_upstream $backend memc_cluster $arg_key;
        memc_pass $backend;
    }

    location /conv-uid-mysql {
        internal;

        set $key "conv-uid-$arg_uid";

        #srcache_fetch GET /memc key=$key;
        #srcache_store PUT /memc key=$key;

        default_type 'application/json';

        drizzle_query "select new_uid as uid from conv_uid where old_uid=$arg_uid";
        drizzle_pass backend;

        rds_json on;
    }

    location /conv-uid {
        internal;
        content_by_lua_file 'html/foo.lua';
    }
    location /api {
        set $uid $arg_uid;
        auth_request /conv-uid;

        echo "Logged in $uid";
    }
--- user_files
>>> foo.lua
local cjson = require('cjson');
local old_uid = ngx.var.uid
-- print('about to run sr')
local res = ngx.location.capture('/conv-uid-mysql?uid=' .. old_uid)
-- print('just have run sr' .. res.body)
if (res.status ~= ngx.HTTP_OK) then
    ngx.exit(res.status)
end
res = cjson.decode(res.body)
if (not res or not res[1] or not res[1].uid or
        not string.match(res[1].uid, '^%d+$')) then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.var.uid = res[1].uid;
-- print('done')
--- request
GET /api?uid=32
--- response_body
Logged in 56
--- no_error_log
[error]
--- timeout: 5



=== TEST 9: working with ngx_auth_request
--- http_config
    upstream backend {
        drizzle_server 127.0.0.1:$TEST_NGINX_MYSQL_PORT protocol=mysql
                       dbname=ngx_test user=ngx_test password=ngx_test;
        drizzle_keepalive max=300 mode=single overflow=ignore;
    }

    upstream memc_a {
        server 127.0.0.1:$TEST_NGINX_MEMCACHED_PORT;
        keepalive 300;
    }

    #upstream_list memc_cluster memc_a memc_b;

--- config
    location /memc {
        internal;

        set $memc_key $arg_key;
        set $memc_exptime $arg_exptime;

        #set_hashed_upstream $backend memc_cluster $arg_key;
        memc_pass memc_a;
    }

    location /conv-mysql {
        internal;

        set $key "conv-uri-$query_string";

        #srcache_fetch GET /memc key=$key;
        #srcache_store PUT /memc key=$key;

        default_type 'application/json';

        set_quote_sql_str $seo_uri $query_string;
        drizzle_query "select url from my_url_map where seo_url=$seo_uri";
        drizzle_pass backend;

        rds_json on;
    }

    location /conv-uid {
        internal;
        content_by_lua_file 'html/foo.lua';
    }

    location /baz {
        set $my_uri $uri;
        auth_request /conv-uid;

        echo_exec /jump $my_uri;
    }

    location /jump {
        internal;
        rewrite ^ $query_string? redirect;
    }
--- user_files
>>> foo.lua
local cjson = require('cjson');
local seo_uri = ngx.var.my_uri
-- print('about to run sr')
local res = ngx.location.capture('/conv-mysql?' .. seo_uri)
if (res.status ~= ngx.HTTP_OK) then
    ngx.exit(res.status)
end
res = cjson.decode(res.body)
if (not res or not res[1] or not res[1].url) then
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end
ngx.var.my_uri = res[1].url;
-- print('done')
--- request
GET /baz
--- response_body_like: 302
--- error_code: 302
--- response_headers
Location: http://localhost:$ServerPort/foo/bar
--- SKIP



=== TEST 10: throw 0
--- config
    location /lua {
        content_by_lua "ngx.say('Hi'); ngx.eof(); ngx.exit(0);ngx.say('world')";
    }
--- request
GET /lua
--- error_code: 200
--- response_body
Hi
--- no_error_log
[error]



=== TEST 11: pcall safe
--- config
    location /lua {
        content_by_lua '
            local function f ()
                ngx.say("hello")
                ngx.exit(200)
            end

            pcall(f)
            ngx.say("world")
        ';
    }
--- request
GET /lua
--- error_code: 200
--- response_body
hello
--- no_error_log
[error]



=== TEST 12: 501 Method Not Implemented
--- config
    location /lua {
        content_by_lua '
            ngx.exit(501)
        ';
    }
--- request
GET /lua
--- error_code: 501
--- response_body_like: 501 (?:Method )?Not Implemented
--- no_error_log
[error]



=== TEST 13: 501 Method Not Implemented
--- config
    location /lua {
        content_by_lua '
            ngx.exit(ngx.HTTP_METHOD_NOT_IMPLEMENTED)
        ';
    }
--- request
GET /lua
--- error_code: 501
--- response_body_like: 501 (?:Method )?Not Implemented
--- no_error_log
[error]



=== TEST 14: throw 403 after sending out headers with 200
--- config
    location /lua {
        rewrite_by_lua '
            ngx.send_headers()
            ngx.say("Hello World")
            ngx.exit(403)
        ';
    }
--- request
GET /lua
--- response_body
Hello World
--- error_log
attempt to set status 403 via ngx.exit after sending out the response status 200
--- no_error_log
[alert]



=== TEST 15: throw 403 after sending out headers with 403
--- config
    location /lua {
        rewrite_by_lua '
            ngx.status = 403
            ngx.send_headers()
            ngx.say("Hello World")
            ngx.exit(403)
        ';
    }
--- request
GET /lua
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]
[alert]



=== TEST 16: throw 403 after sending out headers with 403 (HTTP 1.0 buffering)
--- config
    location /t {
        rewrite_by_lua '
            ngx.status = 403
            ngx.say("Hello World")
            ngx.exit(403)
        ';
    }
--- request
GET /t HTTP/1.0
--- response_body
Hello World
--- error_code: 403
--- no_error_log
[error]
[alert]



=== TEST 17: throw 444 after sending out responses (HTTP 1.0)
--- config
    location /lua {
        content_by_lua "
            ngx.say('ok');
            return ngx.exit(444)
        ";
    }
--- request
GET /lua HTTP/1.0
--- ignore_response
--- log_level: debug
--- no_error_log
lua sending HTTP 1.0 response headers
[error]



=== TEST 18: throw 499 after sending out responses (HTTP 1.0)
--- config
    location /lua {
        content_by_lua "
            ngx.say('ok');
            return ngx.exit(499)
        ";
    }
--- request
GET /lua HTTP/1.0
--- ignore_response
--- log_level: debug
--- no_error_log
lua sending HTTP 1.0 response headers
[error]



=== TEST 19: throw 408 after sending out responses (HTTP 1.0)
--- config
    location /lua {
        content_by_lua "
            ngx.say('ok');
            return ngx.exit(408)
        ";
    }
--- request
GET /lua HTTP/1.0
--- ignore_response
--- log_level: debug
--- no_error_log
lua sending HTTP 1.0 response headers
[error]



=== TEST 20: exit(201) with custom response body
--- config
    location = /t {
        content_by_lua "
            ngx.status = 201
            ngx.say('ok');
            return ngx.exit(201)
        ";
    }
--- request
    GET /t
--- ignore_response
--- log_level: debug
--- no_error_log
lua sending HTTP 1.0 response headers
[error]
[alert]



=== TEST 21: exit 403 in header filter
--- config
    location = /t {
        content_by_lua "ngx.say('hi');";
        header_filter_by_lua '
            return ngx.exit(403)
        ';
    }
--- request
GET /t
--- error_code: 403
--- response_body_like: 403 Forbidden
--- no_error_log
[error]



=== TEST 22: exit 201 in header filter
--- config
    lingering_close always;
    location = /t {
        content_by_lua "ngx.say('hi');";
        header_filter_by_lua '
            return ngx.exit(201)
        ';
    }
--- request
GET /t
--- error_code: 201
--- response_body
--- no_error_log
[error]



=== TEST 23: exit both in header filter and content handler
--- config
    location = /t {
        content_by_lua "ngx.status = 201 ngx.say('hi') ngx.exit(201)";
        header_filter_by_lua '
            return ngx.exit(201)
        ';
    }
--- request
GET /t
--- error_code: 201
--- stap2
/*
F(ngx_http_send_header) {
    printf("=== %d\n", $r->headers_out->status)
    print_ubacktrace()
}
*/
F(ngx_http_lua_header_filter_inline) {
    printf("=== %d\n", $r->headers_out->status)
    print_ubacktrace()
}
F(ngx_http_lua_header_filter_by_chunk).return {
    if ($return == -1) {
        printf("====== header filter by chunk\n")
        print_ubacktrace()
    }
}
--- stap_out
--- response_body
--- no_error_log
[error]
[alert]



=== TEST 24: exit 444 in header filter
--- config
    location = /t {
        content_by_lua "ngx.say('hello world');";
        header_filter_by_lua '
            return ngx.exit(444)
        ';
    }
--- request
GET /t
--- error_code: 444
--- response_body
--- no_error_log
[error]



=== TEST 25: 501 Method Not Implemented
--- config
    location /lua {
        content_by_lua '
            ngx.exit(ngx.HTTP_NOT_IMPLEMENTED)
        ';
    }
--- request
GET /lua
--- error_code: 501
--- response_body_like: 501 (?:Method )?Not Implemented
--- no_error_log
[error]



=== TEST 26: accepts NGX_OK
--- config
    location = /t {
        content_by_lua_block {
            ngx.exit(ngx.OK)
        }
    }
--- request
GET /t
--- response_body
--- no_error_log
[error]



=== TEST 27: accepts NGX_ERROR
--- config
    location = /t {
        content_by_lua_block {
            ngx.exit(ngx.ERROR)
        }
    }
--- request
GET /t
--- error_code:
--- response_body
--- no_error_log
[error]



=== TEST 28: accepts NGX_DECLINED
--- config
    location = /t {
        content_by_lua_block {
            ngx.exit(ngx.DECLINED)
        }
    }
--- request
GET /t
--- error_code:
--- response_body
--- no_error_log
[error]



=== TEST 29: refuses NGX_AGAIN
--- config
    location = /t {
        content_by_lua_block {
            ngx.exit(ngx.AGAIN)
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log eval
qr/\[error\] .*? bad argument to 'ngx.exit': does not accept NGX_AGAIN or NGX_DONE/



=== TEST 30: refuses NGX_DONE
--- config
    location = /t {
        content_by_lua_block {
            ngx.exit(ngx.DONE)
        }
    }
--- request
GET /t
--- error_code: 500
--- response_body_like: 500 Internal Server Error
--- error_log eval
qr/\[error\] .*? bad argument to 'ngx.exit': does not accept NGX_AGAIN or NGX_DONE/
