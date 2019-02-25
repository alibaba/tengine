# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 4);

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.set_escape_uri(" :")
            local r = ndk.set_var.set_unescape_uri("a%20b")
            ngx.say(s)
            ngx.say(r)
        ';
    }
--- request
GET /read
--- response_body
%20%3A
a b



=== TEST 2: directive not found
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.set_escape_uri_blah_blah(" :")
            ngx.say(s)
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 3: directive not found
--- config
    location /read {
        content_by_lua '
            local s = ndk.set_var.content_by_lua(" :")
            ngx.say(s)
        ';
    }
--- request
GET /read
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: directive not found
--- config
    location /read {
        header_filter_by_lua '
            ngx.header.Foo = ndk.set_var.set_escape_uri(" %")
        ';
        echo hi;
    }
--- request
GET /read
--- response_headers
Foo: %20%25
--- response_body
hi



=== TEST 5: bug: ndk.set_var not initialize ngx_http_variable_value_t variable properly
--- config
   location /luaset {
     content_by_lua "

       local version = '2011.10.13+0000'
       local e_version = ndk.set_var.set_encode_base32(version)
       local s_version= ndk.set_var.set_quote_sql_str(version)
       ngx.say(e_version)
       ngx.say(s_version)
     ";
   }
--- request
GET /luaset
--- response_body
68o32c9e64o2sc9j5co30c1g
'2011.10.13+0000'



=== TEST 6: set_by_lua
--- config
    location /read {
        set_by_lua $r '
            return ndk.set_var.set_unescape_uri("a%20b")
        ';
        echo $r;
    }
--- request
GET /read
--- response_body
a b



=== TEST 7: header_filter_by_lua
--- config
    location /read {
        set $foo '';
        content_by_lua '
            ngx.send_headers()
            ngx.say(ngx.var.foo)
        ';
        header_filter_by_lua '
            ngx.var.foo = ndk.set_var.set_unescape_uri("a%20b")
        ';
    }
--- request
GET /read
--- response_body
a b



=== TEST 8: log_by_lua
--- config
    location /read {
        echo ok;
        log_by_lua '
            local foo = ndk.set_var.set_unescape_uri("a%20b")
            ngx.log(ngx.WARN, "foo = ", foo)
        ';
    }
--- request
GET /read
--- response_body
ok
--- wait: 0.1
--- error_log
foo = a b



=== TEST 9: ngx.timer.*
--- config
    location /read {
        echo ok;
        log_by_lua '
            ngx.timer.at(0, function ()
                local foo = ndk.set_var.set_unescape_uri("a%20b")
                ngx.log(ngx.WARN, "foo = ", foo)
            end)
        ';
    }
--- request
GET /read
--- response_body
ok
--- wait: 0.1
--- error_log
foo = a b
--- no_error_log
[error]
